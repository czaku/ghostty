import AppKit
import OSLog

// MARK: - Data types

struct CasperLayout: Codable, Identifiable {
    var id: String { name }
    let name: String
    let savedAt: Date
    let windows: [LayoutWindow]
}

struct LayoutWindow: Codable {
    /// Human label shown in the session banner, e.g. "API", "Frontend", "Tests"
    let sectionName: String
    let frame: SessionFrame           // reuse SessionFrame (x/y/w/h)
    /// Working directory to open the pane in
    let cwd: String?
    /// Command to pre-populate in the prompt (no trailing \n = arrow-up style: visible but not executed)
    let command: String?
    /// If true, the command is executed immediately. Default false (arrow-up style).
    let autoExecute: Bool
}

// MARK: - Manager

/// Saves and restores named multi-window layouts.
///
/// Layouts are stored as JSON files in `~/.config/casper/layouts/`.
/// Each layout captures the frame, section name, CWD, and an optional
/// pre-populated command for each window.
final class LayoutManager {
    static let shared = LayoutManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LayoutManager")

    var layoutsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/casper/layouts", isDirectory: true)
    }

    private init() {}

    // MARK: - Capture from live windows

    /// Snapshots all open TerminalController windows into a named layout.
    func saveLayout(name: String, controllers: [TerminalController]) {
        let windows: [LayoutWindow] = controllers.compactMap { controller in
            guard let window = controller.window else { return nil }
            let frame = window.frame
            let surface = controller.focusedSurface
            let cwd = surface?.pwd
            // Capture the section name from the session banner if set, or the window title
            let sectionName = controller.window?.title ?? "Terminal"
            return LayoutWindow(
                sectionName: sectionName,
                frame: SessionFrame(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height),
                cwd: cwd,
                command: nil,
                autoExecute: false
            )
        }
        guard !windows.isEmpty else { return }
        let layout = CasperLayout(name: name, savedAt: Date(), windows: windows)
        save(layout)
    }

    /// Saves a manually composed layout (e.g. from a "New Layout" dialog).
    func save(_ layout: CasperLayout) {
        do {
            try FileManager.default.createDirectory(at: layoutsURL, withIntermediateDirectories: true)
            let safe = sanitize(layout.name)
            let url = layoutsURL.appendingPathComponent("\(safe).json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(layout).write(to: url, options: .atomic)
            Self.logger.info("Layout saved: \(layout.name)")
        } catch {
            Self.logger.error("Failed to save layout '\(layout.name)': \(error)")
        }
    }

    // MARK: - List & load

    func listLayouts() -> [CasperLayout] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: layoutsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return aDate > bDate
            }
            .compactMap { try? decoder.decode(CasperLayout.self, from: Data(contentsOf: $0)) }
    }

    func deleteLayout(name: String) {
        let url = layoutsURL.appendingPathComponent("\(sanitize(name)).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Restore

    func restoreLayout(_ layout: CasperLayout, ghostty: Ghostty.App) {
        for (i, win) in layout.windows.enumerated() {
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = win.cwd

            if let cmd = win.command, !cmd.isEmpty {
                // Arrow-up style: pre-populate without executing (no trailing newline)
                // Auto-execute: append newline to fire immediately
                config.initialInput = win.autoExecute ? cmd + "\n" : cmd
            }

            let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)

            // Apply frame after a short delay (window needs time to load)
            let frame = win.frame
            let sectionName = win.sectionName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.05) {
                if let window = controller.window {
                    window.setFrame(
                        NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                        display: true
                    )
                }
                // Update the session banner with the section name
                let banner = SessionNameBanner.install(in: controller.window ?? NSWindow())
                banner.setSessionName(sectionName, activity: .idle)
            }
        }
    }

    // MARK: - Helpers

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))).joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
