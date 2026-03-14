import AppKit
import SwiftUI

/// Shows the Session Browser window — a searchable list of saved sessions
/// with restore and delete actions.
final class SessionBrowserController: NSWindowController, NSWindowDelegate {
    static let shared = SessionBrowserController()

    private var ghosttyApp: Ghostty.App?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Session Browser"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(ghostty: Ghostty.App) {
        ghosttyApp = ghostty
        let view = SessionBrowserView(ghostty: ghostty) {
            self.window?.close()
        }
        window?.contentView = NSHostingView(rootView: view)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ghosttyApp = nil
    }
}
