import AppKit
import Foundation
import GhosttyKit

/// Handles ⌘+click on file:line references in terminal surfaces.
///
/// When the user holds ⌘ and clicks in a terminal pane, we read the line of
/// text at the clicked row, search for a `path:line` or `path:line:col`
/// pattern, and open the file in the configured editor.
enum FileLinkHandler {

    // MARK: - Pattern

    // Matches: /some/path/file.ext:42 or /some/path/file.ext:42:7
    // Requires an absolute path (leading /) to avoid false positives.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"(/[^\s:"'<>|]+\.[a-zA-Z0-9_]+):(\d+)(?::(\d+))?"#
    )

    // MARK: - Hit test

    /// Given a mouse-down event, determines whether it was a ⌘+click on a
    /// SurfaceView and, if so, extracts and opens any file:line reference on
    /// the clicked row. Returns true if the event was consumed.
    @MainActor
    @discardableResult
    static func handleMouseDown(_ event: NSEvent, editor: String) -> Bool {
        guard event.type == .leftMouseDown,
              event.modifierFlags.contains(.command),
              let window = event.window
        else { return false }

        // Find the SurfaceView under the click
        let windowPoint = event.locationInWindow
        guard let hit = window.contentView?.hitTest(windowPoint),
              let surfaceView = surfaceViewInHierarchy(hit)
        else { return false }

        // Convert to view-local coordinates (AppKit: y=0 at bottom)
        let viewPoint = surfaceView.convert(windowPoint, from: nil)
        let cellHeight = surfaceView.cellSize.height
        guard cellHeight > 0 else { return false }

        // Row 0 is at the top of the view; AppKit y=0 is at the bottom.
        let viewHeight = surfaceView.bounds.height
        let row = Int((viewHeight - viewPoint.y) / cellHeight)

        // Read the full screen text
        guard let surface = surfaceView.surface else { return false }
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0, y: 0),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0, y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surface, sel, &text) else { return false }
        defer { ghostty_surface_free_text(surface, &text) }

        let screenText = String(cString: text.text)
        guard let link = fileLink(inText: screenText, row: row) else { return false }

        open(path: link.path, line: link.line, col: link.col, editor: editor)
        return true
    }

    // MARK: - Text parsing

    static func fileLink(inText text: String, row: Int) -> (path: String, line: Int, col: Int)? {
        let lines = text.components(separatedBy: "\n")
        guard row >= 0, row < lines.count else { return nil }
        let lineStr = lines[row]
        let ns = lineStr as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = linkPattern.firstMatch(in: lineStr, range: range) else { return nil }

        let path = ns.substring(with: match.range(at: 1))
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let lineNum = Int(ns.substring(with: match.range(at: 2))) ?? 1
        let colNum = match.range(at: 3).location != NSNotFound
            ? Int(ns.substring(with: match.range(at: 3))) ?? 1
            : 1
        return (path, lineNum, colNum)
    }

    // MARK: - Open

    static func open(path: String, line: Int, col: Int = 1, editor: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        switch editor {
        case "cursor":
            launch(command: "cursor", args: ["-g", "\(path):\(line):\(col)"])
        case "code":
            launch(command: "code", args: ["-g", "\(path):\(line):\(col)"])
        case "zed":
            launch(command: "zed", args: ["\(path):\(line):\(col)"])
        case "nvim":
            openInTerminalEditor("nvim", path: path, line: line)
        case "vim":
            openInTerminalEditor("vim", path: path, line: line)
        default:
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    // MARK: - Private helpers

    private static func launch(command: String, args: [String]) {
        let candidates = [
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/bin/\(command)",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: candidate)
            proc.arguments = args
            try? proc.run()
            return
        }
        // Fallback: open -a <App>
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", command.capitalized] + args
        try? proc.run()
    }

    private static func openInTerminalEditor(_ editor: String, path: String, line: Int) {
        NotificationCenter.default.post(
            name: .casperOpenInTerminalEditor,
            object: nil,
            userInfo: ["editor": editor, "path": path, "line": line]
        )
    }

    @MainActor
    private static func surfaceViewInHierarchy(_ view: NSView) -> Ghostty.SurfaceView? {
        if let sv = view as? Ghostty.SurfaceView { return sv }
        if let parent = view.superview { return surfaceViewInHierarchy(parent) }
        return nil
    }
}

extension Notification.Name {
    static let casperOpenInTerminalEditor = Notification.Name("casper.openInTerminalEditor")
}
