import AppKit

/// A transparent full-frame overlay view that draws a colored inset border.
///
/// Added as the topmost subview of a window's contentView so it renders on top
/// of the Metal terminal surface. Mouse events pass through completely.
final class ActivityBorderView: NSView {

    /// Accent colour driven by the window's CasperTheme.
    var themeAccent: NSColor = .systemBlue

    var activity: PaneActivity = .idle {
        didSet {
            guard activity != oldValue else { return }
            needsDisplay = true
            // Animate opacity change
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.animator().alphaValue = activity == .idle ? 0 : 1
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0
        wantsLayer = true
        // The view itself must not draw a background — only the border stroke
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Hit testing passthrough

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let (color, width): (NSColor, CGFloat) = switch activity {
        case .waitingForInput: (.systemOrange,  3)
        case .executing:       (themeAccent,    2)
        case .idle:            (.clear,         0)
        }

        guard width > 0 else { return }

        // Draw a rounded-rect border inset slightly so it sits entirely within the view
        let inset = width / 2 + 0.5
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: 6,
            yRadius: 6
        )
        path.lineWidth = width
        color.withAlphaComponent(0.85).setStroke()
        path.stroke()

        // Subtle glow — draw a wider, very transparent stroke beneath
        if activity == .waitingForInput {
            let glowPath = NSBezierPath(
                roundedRect: bounds.insetBy(dx: inset + 2, dy: inset + 2),
                xRadius: 7,
                yRadius: 7
            )
            glowPath.lineWidth = width + 4
            color.withAlphaComponent(0.15).setStroke()
            glowPath.stroke()
        }
    }

    // MARK: - Attach / detach

    /// Attaches the overlay to a window's contentView, or updates the existing one.
    @discardableResult
    static func install(in window: NSWindow) -> ActivityBorderView {
        if let existing = window.contentView?.subviews.compactMap({ $0 as? ActivityBorderView }).first {
            return existing
        }
        let view = ActivityBorderView(frame: window.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(view, positioned: .above, relativeTo: nil)
        return view
    }
}
