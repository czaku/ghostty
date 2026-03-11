import AppKit
import GhosttyKit
import OSLog

// MARK: - Session data types

struct SessionData: Codable {
    let version: Int
    let savedAt: Date
    let windows: [SessionWindow]
}

struct SessionWindow: Codable {
    let frame: SessionFrame
    let surfaces: [SessionSurface]
}

struct SessionFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SessionSurface: Codable {
    let uuid: String
    let cwd: String?
    let title: String
    let scrollback: String
}

// MARK: - SessionManager

final class SessionManager {
    static let shared = SessionManager()
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SessionManager")

    private static let maxScrollbackLines = 10_000

    private var periodicSaveTimer: Timer?

    // ~/.../Application Support/ghostty/sessions/
    var sessionsURL: URL {
        let stateDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return stateDir.appendingPathComponent("Application Support/ghostty/sessions", isDirectory: true)
    }

    // ~/.../Application Support/ghostty/current-session.json
    var currentSessionURL: URL {
        let stateDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return stateDir.appendingPathComponent("Application Support/ghostty/current-session.json")
    }

    // ~/.../Application Support/ghostty/restore-pending.json
    // Written by `ghostty +restore-session` to trigger a restore on next launch.
    var pendingRestoreURL: URL {
        let stateDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return stateDir.appendingPathComponent("Application Support/ghostty/restore-pending.json")
    }

    /// If a pending restore file exists, loads and returns the session, then deletes the marker.
    func consumePendingRestore() -> SessionData? {
        let url = pendingRestoreURL
        guard let pathData = try? Data(contentsOf: url),
              let path = String(data: pathData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let sessionURL = URL(fileURLWithPath: path)
        return try? loadSession(url: sessionURL)
    }

    private init() {}

    // MARK: - Save

    func saveSession(controllers: [TerminalController]) {
        let windows: [SessionWindow] = controllers.compactMap { sessionWindow(from: $0) }
        guard !windows.isEmpty else { return }

        let data = SessionData(version: 1, savedAt: Date(), windows: windows)
        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            let filename = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-") + ".json"
            let url = sessionsURL.appendingPathComponent(filename)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: .atomic)
            Self.logger.info("Session saved to \(url.path)")
        } catch {
            Self.logger.error("Failed to save session: \(error)")
        }
    }

    /// Saves to current-session.json (overwritten each time, used for crash recovery and periodic save).
    func saveCurrentSession(controllers: [TerminalController]) {
        let windows: [SessionWindow] = controllers.compactMap { sessionWindow(from: $0) }
        guard !windows.isEmpty else { return }

        let data = SessionData(version: 1, savedAt: Date(), windows: windows)
        do {
            try FileManager.default.createDirectory(
                at: currentSessionURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(data)
            try encoded.write(to: currentSessionURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save current session: \(error)")
        }
    }

    // MARK: - Crash Recovery

    /// Returns true if a current-session.json exists from a previous crash.
    func crashRecoverySessionExists() -> Bool {
        return FileManager.default.fileExists(atPath: currentSessionURL.path)
    }

    /// Deletes current-session.json. Call on clean exit.
    func clearCrashRecovery() {
        try? FileManager.default.removeItem(at: currentSessionURL)
    }

    // MARK: - Periodic Save

    func startPeriodicSave(interval: TimeInterval) {
        stopPeriodicSave()
        let effectiveInterval = max(30, interval)
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            self?.saveCurrentSession(controllers: TerminalController.all)
        }
    }

    func stopPeriodicSave() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }

    // MARK: - List & Load

    func listSessions() -> [(name: String, url: URL)] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return aDate > bDate
            }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }

    func latestSessionURL() -> URL? {
        listSessions().first?.url
    }

    func loadSession(url: URL) throws -> SessionData {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionData.self, from: data)
    }

    // MARK: - Restore

    func restoreSession(_ session: SessionData, ghostty: Ghostty.App) {
        for window in session.windows {
            restoreWindow(window, ghostty: ghostty)
        }
    }

    private func restoreWindow(_ windowData: SessionWindow, ghostty: Ghostty.App) {
        guard let firstSurface = windowData.surfaces.first else { return }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = firstSurface.cwd
        if !firstSurface.scrollback.isEmpty {
            config.initialInput = makeScrollbackCommand(firstSurface.scrollback)
        }

        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)

        // For additional surfaces (splits), open as new tabs
        for surface in windowData.surfaces.dropFirst() {
            var tabConfig = Ghostty.SurfaceConfiguration()
            tabConfig.workingDirectory = surface.cwd
            if !surface.scrollback.isEmpty {
                tabConfig.initialInput = makeScrollbackCommand(surface.scrollback)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: Ghostty.Notification.ghosttyNewTab,
                    object: controller.focusedSurface,
                    userInfo: [Ghostty.Notification.NewSurfaceConfigKey: tabConfig]
                )
            }
        }

        // Restore window frame
        if let window = controller.window {
            let frame = windowData.frame
            let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            window.setFrame(rect, display: true)
        }
    }

    /// Writes scrollback to a temp file and returns a shell command that cats it.
    /// The cat output appears visually in the terminal without re-executing any commands.
    private func makeScrollbackCommand(_ scrollback: String) -> String {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_scrollback_\(UUID().uuidString).txt")
        do {
            try scrollback.write(to: tmpURL, atomically: true, encoding: .utf8)
            let path = Ghostty.Shell.quote(tmpURL.path)
            return "cat \(path); rm -f \(path)\n"
        } catch {
            Self.logger.error("Failed to write scrollback temp file: \(error)")
            return ""
        }
    }

    // MARK: - Private helpers

    private func sessionWindow(from controller: TerminalController) -> SessionWindow? {
        guard let window = controller.window else { return nil }
        let frame = window.frame
        let sessionFrame = SessionFrame(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
        let surfaces = controller.surfaceTree.compactMap { sessionSurface(from: $0) }
        guard !surfaces.isEmpty else { return nil }
        return SessionWindow(frame: sessionFrame, surfaces: surfaces)
    }

    private func sessionSurface(from view: Ghostty.SurfaceView) -> SessionSurface? {
        let scrollback = readScrollback(from: view)
        return SessionSurface(
            uuid: view.id.uuidString,
            cwd: view.pwd,
            title: view.title,
            scrollback: scrollback
        )
    }

    private func readScrollback(from view: Ghostty.SurfaceView) -> String {
        guard let surface = view.surface else { return "" }
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
        defer { ghostty_surface_free_text(surface, &text) }
        let full = String(cString: text.text)
        // Cap to maxScrollbackLines to avoid enormous files
        let lines = full.components(separatedBy: "\n")
        if lines.count > Self.maxScrollbackLines {
            return lines.suffix(Self.maxScrollbackLines).joined(separator: "\n")
        }
        return full
    }
}
