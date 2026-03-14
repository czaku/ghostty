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
    /// Full split-tree geometry saved since version 2.
    /// Nil on sessions saved by older versions — fall back to `surfaces`.
    let splitTree: SessionSplitNode?
    /// Flat surface list. Kept for backward-compat decoding of v1 sessions.
    let surfaces: [SessionSurface]

    init(frame: SessionFrame, splitTree: SessionSplitNode, surfaces: [SessionSurface]) {
        self.frame = frame
        self.splitTree = splitTree
        self.surfaces = surfaces
    }

    /// Convenience init for v1 sessions and tests — no split tree.
    init(frame: SessionFrame, surfaces: [SessionSurface]) {
        self.frame = frame
        self.splitTree = nil
        self.surfaces = surfaces
    }
}

/// A codable mirror of SplitTree.Node that stores SessionSurface at the leaves.
indirect enum SessionSplitNode: Codable {
    case leaf(SessionSurface)
    case split(direction: SplitDirection, ratio: Double, left: SessionSplitNode, right: SessionSplitNode)

    enum SplitDirection: String, Codable {
        case horizontal
        case vertical
    }

    /// All leaf surfaces in traversal order.
    var surfaces: [SessionSurface] {
        switch self {
        case .leaf(let s): return [s]
        case .split(_, _, let l, let r): return l.surfaces + r.surfaces
        }
    }
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
    /// Name of the foreground process at save time if it's on the replay whitelist
    /// (e.g. "claude", "claude-edge", "nvim"). Nil means restore to a bare prompt.
    let foregroundProcess: String?
    /// Sweech profile that was active at save time, if the process is a Sweech-managed
    /// wrapper (e.g. claude-pole). Used to display provider/model info and to set
    /// CLAUDE_CONFIG_DIR on restore.
    let sweechProfile: SweechProfile?

    init(
        uuid: String,
        cwd: String?,
        title: String,
        scrollback: String,
        foregroundProcess: String? = nil,
        sweechProfile: SweechProfile? = nil
    ) {
        self.uuid = uuid
        self.cwd = cwd
        self.title = title
        self.scrollback = scrollback
        self.foregroundProcess = foregroundProcess
        self.sweechProfile = sweechProfile
    }
}

// MARK: - SessionManager

final class SessionManager {
    static let shared = SessionManager()
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SessionManager")

    /// Injected from the live Ghostty config so session limits are configurable.
    var config: Ghostty.Config? = nil

    private var periodicSaveTimer: Timer?

    /// Root of this app's Application Support directory, keyed by bundle ID so
    /// production Ghostty and the czaku fork never share state.
    private var appSupportURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.czaku.casper"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // ~/.../Application Support/<bundleID>/sessions/
    var sessionsURL: URL {
        appSupportURL.appendingPathComponent("sessions", isDirectory: true)
    }

    // ~/.../Application Support/<bundleID>/current-session.json
    var currentSessionURL: URL {
        appSupportURL.appendingPathComponent("current-session.json")
    }

    // ~/.../Application Support/<bundleID>/restore-pending.json
    // Written by `ghostty +restore-session` to trigger a restore on next launch.
    var pendingRestoreURL: URL {
        appSupportURL.appendingPathComponent("restore-pending.json")
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

    func saveSession(controllers: [TerminalController], named name: String? = nil) {
        let windows: [SessionWindow] = controllers.compactMap { sessionWindow(from: $0) }
        guard !windows.isEmpty else { return }

        let data = SessionData(version: 1, savedAt: Date(), windows: windows)
        do {
            try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            let filename: String
            if let name, !name.isEmpty {
                // Sanitise: replace path-unsafe chars with dashes
                let safe = name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted).joined(separator: "-")
                filename = safe + ".json"
            } else {
                filename = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-") + ".json"
            }
            let url = sessionsURL.appendingPathComponent(filename)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: .atomic)
            Self.logger.info("Session saved to \(url.path)")
            pruneOldSessions()
        } catch {
            Self.logger.error("Failed to save session: \(error)")
        }
    }

    /// Deletes session files older than `sessionRetentionDays`, keeping at least one.
    private func pruneOldSessions() {
        let retentionDays = config?.sessionRetentionDays ?? 30
        let cutoff = Date().addingTimeInterval(-retentionDays * 86400)
        let all = listSessions()
        guard all.count > 1 else { return }
        for entry in all.dropLast(1) {
            guard let modified = (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: entry.url)
            Self.logger.info("Pruned old session: \(entry.url.lastPathComponent)")
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
        let frame = windowData.frame
        let origin = NSPoint(x: frame.x, y: frame.y)

        if let splitNode = windowData.splitTree,
           let tree = buildSplitTree(from: splitNode, ghostty: ghostty) {
            // Full split-geometry restore: build the tree and hand it directly to the controller.
            let controller = TerminalController.newWindow(ghostty, tree: tree, position: origin)
            if let window = controller.window {
                let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                window.setFrame(rect, display: true)
            }
        } else {
            // Fallback for v1 sessions (no splitTree): open first surface as window,
            // rest as tabs.
            guard let firstSurface = windowData.surfaces.first else { return }
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = firstSurface.cwd
            config.initialInput = initialInput(for: firstSurface)
            let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)

            for surface in windowData.surfaces.dropFirst() {
                var tabConfig = Ghostty.SurfaceConfiguration()
                tabConfig.workingDirectory = surface.cwd
                tabConfig.initialInput = initialInput(for: surface)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: Ghostty.Notification.ghosttyNewTab,
                        object: controller.focusedSurface,
                        userInfo: [Ghostty.Notification.NewSurfaceConfigKey: tabConfig]
                    )
                }
            }
            if let window = controller.window {
                let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                window.setFrame(rect, display: true)
            }
        }
    }

    /// Recursively builds a SplitTree<SurfaceView> from the saved session node.
    private func buildSplitTree(
        from node: SessionSplitNode,
        ghostty: Ghostty.App
    ) -> SplitTree<Ghostty.SurfaceView>? {
        guard let treeNode = buildSplitNode(from: node, ghostty: ghostty) else { return nil }
        return SplitTree(root: treeNode, zoomed: nil)
    }

    private func buildSplitNode(
        from node: SessionSplitNode,
        ghostty: Ghostty.App
    ) -> SplitTree<Ghostty.SurfaceView>.Node? {
        guard let ghosttyApp = ghostty.app else { return nil }
        switch node {
        case .leaf(let surface):
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = surface.cwd
            config.initialInput = initialInput(for: surface)
            let view = Ghostty.SurfaceView(ghosttyApp, baseConfig: config)
            return .leaf(view: view)
        case .split(let direction, let ratio, let left, let right):
            guard let leftNode = buildSplitNode(from: left, ghostty: ghostty),
                  let rightNode = buildSplitNode(from: right, ghostty: ghostty) else { return nil }
            let dir: SplitTree<Ghostty.SurfaceView>.Direction = direction == .horizontal ? .horizontal : .vertical
            return .split(.init(direction: dir, ratio: ratio, left: leftNode, right: rightNode))
        }
    }

    /// Builds the full `initialInput` string for a surface on restore.
    ///
    /// Sequencing:
    /// 1. If there is scrollback, replay it visually via `cat tmpfile; rm tmpfile`.
    /// 2. If a replayable foreground process was saved, append its restore command.
    ///
    /// For `claude`, the restore command is `claude --continue`.
    /// For Sweech-managed wrappers (e.g. `claude-pole`), the wrapper script is re-run
    /// as-is — it already injects `CLAUDE_CONFIG_DIR` itself.
    /// For bare `claude` that was run inside a Sweech config dir, we set
    /// `CLAUDE_CONFIG_DIR` explicitly so the conversation context is preserved.
    private func initialInput(for surface: SessionSurface) -> String? {
        var parts: [String] = []

        if !surface.scrollback.isEmpty {
            parts.append(makeScrollbackCommand(surface.scrollback))
        }

        if let proc = surface.foregroundProcess {
            var cmd = ProcessDetector.restoreCommand(for: proc)
            // For bare `claude` with a Sweech profile saved, re-inject CLAUDE_CONFIG_DIR.
            // (Sweech wrapper scripts inject this themselves; bare `claude` does not.)
            if proc == "claude", let configDir = surface.sweechProfile.flatMap({ SweechReader.configDir(forCommand: $0.commandName) }) {
                let quoted = Ghostty.Shell.quote(configDir)
                cmd = "CLAUDE_CONFIG_DIR=\(quoted) \(cmd)"
            }
            parts.append(cmd + "\n")
        }

        return parts.isEmpty ? nil : parts.joined()
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
        guard let root = controller.surfaceTree.root,
              let splitNode = sessionSplitNode(from: root) else { return nil }
        let surfaces = splitNode.surfaces
        return SessionWindow(frame: sessionFrame, splitTree: splitNode, surfaces: surfaces)
    }

    private func sessionSplitNode(from node: SplitTree<Ghostty.SurfaceView>.Node) -> SessionSplitNode? {
        switch node {
        case .leaf(let view):
            guard let surface = sessionSurface(from: view) else { return nil }
            return .leaf(surface)
        case .split(let split):
            guard let left = sessionSplitNode(from: split.left),
                  let right = sessionSplitNode(from: split.right) else { return nil }
            let dir: SessionSplitNode.SplitDirection = split.direction == .horizontal ? .horizontal : .vertical
            return .split(direction: dir, ratio: split.ratio, left: left, right: right)
        }
    }

    private func sessionSurface(from view: Ghostty.SurfaceView) -> SessionSurface? {
        let scrollback = readScrollback(from: view)
        let patterns = config?.sessionReplayCommands ?? ProcessDetector.replayablePatterns
        let foreground = view.pwd.flatMap { ProcessDetector.replayableProcess(inDirectory: $0, patterns: patterns) }
        // If the process is a Sweech-managed wrapper, enrich with profile metadata.
        let sweech = foreground.flatMap { SweechReader.profile(forCommand: $0) }
        return SessionSurface(
            uuid: view.id.uuidString,
            cwd: view.pwd,
            title: view.title,
            scrollback: scrollback,
            foregroundProcess: foreground,
            sweechProfile: sweech
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
        // Cap scrollback to the configured limit to avoid enormous files
        let maxLines = config?.sessionMaxScrollback ?? 10_000
        let lines = full.components(separatedBy: "\n")
        if lines.count > maxLines {
            return lines.suffix(maxLines).joined(separator: "\n")
        }
        return full
    }
}
