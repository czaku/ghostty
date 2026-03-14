import AppKit

/// A near-invisible tinted overlay that gives each window a subtle colour cast
/// matching its CasperTheme. Sits below the ActivityBorderView so it doesn't
/// interfere with terminal content.
final class CasperThemeTintView: NSView {

    var tintColor: NSColor = .clear {
        didSet {
            layer?.backgroundColor = tintColor.cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    @discardableResult
    static func install(in window: NSWindow, color: NSColor) -> CasperThemeTintView {
        if let existing = window.contentView?.subviews
            .compactMap({ $0 as? CasperThemeTintView }).first {
            existing.tintColor = color
            return existing
        }
        let view = CasperThemeTintView(frame: window.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        // Add above the terminal Metal surface. Border/action overlays are installed
        // after this call (in updateActivityVisuals) so they naturally stack on top.
        window.contentView?.addSubview(view, positioned: .above, relativeTo: nil)
        view.tintColor = color
        return view
    }
}
