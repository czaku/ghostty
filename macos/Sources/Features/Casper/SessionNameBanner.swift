import AppKit

/// A `NSTitlebarAccessoryViewController` that shows the session/window name
/// in a blurred, frosted-glass banner below the titlebar.
///
/// This view is part of the window's chrome, so it appears in Mission Control
/// thumbnails and Exposé, making it easy to identify each Casper window at a
/// glance even when many windows are open.
///
/// Usage:
///   let banner = SessionNameBanner()
///   banner.attach(to: window, name: "MY-PROJECT")
final class SessionNameBanner: NSTitlebarAccessoryViewController {

    private let label = NSTextField(labelWithString: "")
    private let effectView = NSVisualEffectView()

    // MARK: - View lifecycle

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Blurred material background
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        // Session name label
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            container.heightAnchor.constraint(equalToConstant: 28),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Place the banner just below the titlebar (above the terminal content)
        layoutAttribute = .bottom
        // Don't show a separator line between titlebar and banner
        fullScreenMinHeight = 0
    }

    // MARK: - Public API

    func setSessionName(_ name: String, activity: PaneActivity) {
        let prefix: String = switch activity {
        case .waitingForInput: "⏸ "
        case .executing:       "▶ "
        case .idle:            ""
        }
        label.stringValue = prefix + name
        // Tint the effect view subtly based on activity
        switch activity {
        case .waitingForInput:
            effectView.material = .hudWindow
            label.textColor = NSColor.systemOrange
        case .executing:
            effectView.material = .hudWindow
            label.textColor = NSColor.systemBlue
        case .idle:
            effectView.material = .hudWindow
            label.textColor = NSColor.secondaryLabelColor
        }
    }

    // MARK: - Attach / detach

    /// Installs or retrieves the banner for a window.
    static func install(in window: NSWindow) -> SessionNameBanner {
        if let existing = window.titlebarAccessoryViewControllers
            .compactMap({ $0 as? SessionNameBanner }).first {
            return existing
        }
        let banner = SessionNameBanner()
        window.addTitlebarAccessoryViewController(banner)
        return banner
    }

    static func remove(from window: NSWindow) {
        let banners = window.titlebarAccessoryViewControllers
            .compactMap { $0 as? SessionNameBanner }
        for banner in banners {
            if let idx = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === banner }) {
                window.removeTitlebarAccessoryViewController(at: idx)
            }
        }
    }
}
