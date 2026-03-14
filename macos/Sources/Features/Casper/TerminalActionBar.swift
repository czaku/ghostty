import AppKit

// MARK: - TerminalActionBar

/// A floating action bar that appears in the bottom-right corner of a terminal window
/// when the user hovers. Provides quick access to AI, session, broadcast, and search.
final class TerminalActionBar: NSView {

    // MARK: - Layout

    private static let barHeight: CGFloat = 42
    private static let barPadding: CGFloat = 16   // inset from window edge
    private static let buttonSize: CGFloat = 28
    private static let buttonSpacing: CGFloat = 4
    private static let cornerRadius: CGFloat = 12

    // MARK: - Subviews

    private let blur: NSVisualEffectView
    private let activityDot: NSView
    private let aiButton: ActionButton
    private let saveButton: ActionButton
    private let broadcastButton: ActionButton
    private let searchButton: ActionButton
    private let themeButton: ActionButton

    // MARK: - State

    private weak var controller: TerminalController?
    private var hideTimer: Timer?
    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    init(controller: TerminalController) {
        self.controller = controller

        // Blur background
        blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.cornerRadius

        // Activity indicator dot
        activityDot = NSView()
        activityDot.wantsLayer = true

        // Buttons
        aiButton        = ActionButton(imageName: "CasperIcons/ai",           tooltip: "Ask AI (⌘⇧A)")
        saveButton      = ActionButton(imageName: "CasperIcons/save",         tooltip: "Save Session")
        broadcastButton = ActionButton(imageName: "CasperIcons/broadcasting", tooltip: "Toggle Broadcast")
        searchButton    = ActionButton(imageName: "CasperIcons/search",       tooltip: "Find")
        themeButton     = ActionButton(imageName: "",                          tooltip: "Switch Theme")

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Build layout
        addSubview(blur)
        blur.addSubview(activityDot)
        blur.addSubview(aiButton)
        blur.addSubview(saveButton)
        blur.addSubview(broadcastButton)
        blur.addSubview(searchButton)
        blur.addSubview(themeButton)

        // Wire actions
        aiButton.target = self
        aiButton.action = #selector(askAI)
        saveButton.target = self
        saveButton.action = #selector(saveSession)
        broadcastButton.target = self
        broadcastButton.action = #selector(toggleBroadcast)
        searchButton.target = self
        searchButton.action = #selector(toggleSearch)
        themeButton.target = self
        themeButton.action = #selector(cycleTheme)

        // Initially hidden
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let bSize = Self.buttonSize
        let spacing = Self.buttonSpacing
        let dotSize: CGFloat = 10

        // Arrange buttons left to right inside blur
        let totalWidth = dotSize + spacing + CGFloat(5) * (bSize + spacing) - spacing
        let startX = (blur.bounds.width - totalWidth) / 2

        var x = startX
        let midY = blur.bounds.midY

        // Activity dot
        activityDot.frame = NSRect(
            x: x,
            y: midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        activityDot.layer?.cornerRadius = dotSize / 2
        x += dotSize + spacing

        // Icon buttons
        for button in [aiButton, saveButton, broadcastButton, searchButton, themeButton] {
            button.frame = NSRect(
                x: x,
                y: midY - bSize / 2,
                width: bSize,
                height: bSize
            )
            x += bSize + spacing
        }

        blur.frame = bounds
    }

    // MARK: - Sizing

    /// Computes the frame for the bar positioned in the bottom-right of a parent view.
    static func barFrame(in parent: NSView) -> NSRect {
        let buttons = 4
        let bSize = buttonSize
        let spacing = buttonSpacing
        let dotSize: CGFloat = 10
        let innerWidth = dotSize + spacing + CGFloat(5) * (bSize + spacing)
        let hPad: CGFloat = 16
        let width = innerWidth + hPad * 2
        let x = parent.bounds.maxX - width - barPadding
        let y = barPadding
        return NSRect(x: x, y: y, width: width, height: barHeight)
    }

    // MARK: - State updates

    func update(activity: PaneActivity, broadcasting: Bool) {
        let theme = controller?.casperTheme ?? .wraith

        // Activity dot color
        let dotColor: NSColor = switch activity {
        case .waitingForInput: .systemOrange
        case .executing:       theme.accentColor
        case .idle:            .tertiaryLabelColor
        }
        activityDot.layer?.backgroundColor = dotColor.cgColor

        // Broadcast button highlight
        broadcastButton.isActive = broadcasting

        // Theme button: show theme initial letter
        themeButton.title = String(theme.displayName.prefix(1))
        themeButton.image = nil
        themeButton.font = .systemFont(ofSize: 13, weight: .semibold)
        themeButton.contentTintColor = theme.accentColor
        themeButton.toolTip = "Theme: \(theme.displayName) (click to cycle)"
    }

    // MARK: - Hover show/hide

    func attachTracking(to parent: NSView) {
        if let existing = trackingArea {
            parent.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: parent.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        parent.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        showBar()
    }

    override func mouseExited(with event: NSEvent) {
        scheduleHide()
    }

    override func mouseMoved(with event: NSEvent) {
        showBar()
        scheduleHide()
    }

    private func showBar() {
        hideTimer?.invalidate()
        hideTimer = nil
        isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.animator().alphaValue = 0
            }, completionHandler: {
                if self.alphaValue < 0.01 { self.isHidden = true }
            })
        }
    }

    // MARK: - Hit testing
    // The bar itself receives clicks — only the transparent background area passes through

    override func hitTest(_ point: NSPoint) -> NSView? {
        // If we're fully transparent, pass through
        guard alphaValue > 0.01 else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Actions

    @objc private func askAI() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        AskAIAction.run(ghostty: appDelegate.ghostty, config: appDelegate.ghostty.config)
    }

    @objc private func saveSession() {
        NotificationCenter.default.post(name: .casperSaveSession, object: nil)
    }

    @objc private func toggleBroadcast() {
        controller?.broadcastMode.toggle()
        if let controller {
            update(activity: controller.activityState, broadcasting: controller.broadcastMode)
        }
    }

    @objc private func toggleSearch() {
        NSApp.sendAction(Selector(("find:")), to: nil, from: self)
    }

    @objc private func cycleTheme() {
        guard let controller else { return }
        let all = CasperTheme.allCases
        let current = controller.casperTheme
        let next = all[(all.firstIndex(of: current)! + 1) % all.count]
        CasperThemeManager.shared.apply(next, to: controller)
        update(activity: controller.activityState, broadcasting: controller.broadcastMode)
    }

    // MARK: - Install / detach

    @discardableResult
    static func install(in window: NSWindow, controller: TerminalController) -> TerminalActionBar? {
        guard let contentView = window.contentView else { return nil }

        if let existing = contentView.subviews.compactMap({ $0 as? TerminalActionBar }).first {
            existing.update(activity: controller.activityState, broadcasting: controller.broadcastMode)
            return existing
        }

        let bar = TerminalActionBar(controller: controller)
        bar.frame = barFrame(in: contentView)
        bar.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(bar, positioned: .above, relativeTo: nil)
        bar.attachTracking(to: contentView)
        bar.update(activity: controller.activityState, broadcasting: controller.broadcastMode)
        return bar
    }

}

// MARK: - Notification names

extension Notification.Name {
    static let casperSaveSession = Notification.Name("casperSaveSession")
}

// MARK: - ActionButton

/// A small borderless icon button with hover highlight.
final class ActionButton: NSButton {
    var isActive: Bool = false {
        didSet { needsDisplay = true }
    }

    private let imageName: String

    init(imageName: String, tooltip: String) {
        self.imageName = imageName
        super.init(frame: .zero)
        self.toolTip = tooltip
        isBordered = false
        bezelStyle = .regularSquare
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 6

        if let img = NSImage(named: imageName) {
            img.isTemplate = false
            image = img
        } else {
            // Fallback: SF Symbol
            let fallback = imageName.contains("ai") ? "brain" :
                           imageName.contains("save") ? "square.and.arrow.down" :
                           imageName.contains("broadcast") ? "dot.radiowaves.left.and.right" : "magnifyingglass"
            image = NSImage(systemSymbolName: fallback, accessibilityDescription: tooltip)
        }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = isActive
                ? NSColor.systemBlue.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isActive {
            NSColor.systemBlue.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
