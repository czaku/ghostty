import AppKit
import GhosttyKit
import OSLog

// MARK: - State

/// The inferred activity state of a terminal pane based on its visible content.
enum PaneActivity: Equatable {
    /// The shell prompt is visible and nothing is running.
    case idle
    /// A process is actively writing output.
    case executing
    /// An AI agent or interactive program is waiting for human input.
    case waitingForInput
}

// MARK: - Monitor

/// Periodically reads the last few lines of every terminal surface and infers
/// its activity state from text patterns. Detected changes are dispatched to
/// the owning `TerminalController` on the main thread.
final class PaneActivityMonitor {
    static let shared = PaneActivityMonitor()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PaneActivityMonitor")

    private var timer: Timer?

    /// Text snapshot from the previous poll cycle — used to detect output changes.
    private var lastTexts: [ObjectIdentifier: String] = [:]

    // MARK: - Waiting-for-input patterns

    /// Substrings that indicate an AI agent or interactive prompt is waiting for a
    /// human decision. Case-insensitive comparison is used at runtime.
    private static let waitingPatterns: [String] = [
        // Claude Code
        "bypass permissions on",
        "would you like to proceed",
        "◆",   // Claude Code interactive question bullet
        "◇",   // Claude Code interactive option
        ">> ",  // Claude Code reply prompt
        // Generic interactive prompts
        "[y/n]",
        "[Y/n]",
        "[N/y]",
        "[yes/no]",
        "proceed?",
        "do you want to",
        "press any key",
        "continue? ",
    ]

    /// Suffixes on the last non-empty line that indicate a shell prompt is waiting.
    private static let idlePromptSuffixes: [String] = [
        "$ ", "$\t",    // bash/zsh
        "% ", "%\t",    // zsh
        "# ",           // root
        "> ",           // fish / PS2
        "❯ ",           // starship / pure
        "→ ",
    ]

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func poll() {
        for controller in TerminalController.all {
            guard let surface = controller.focusedSurface else { continue }
            let text = readLastLines(surface, count: 10)
            let id = ObjectIdentifier(controller)
            let previous = lastTexts[id]
            lastTexts[id] = text

            let state = detectState(text: text, changedFromPrevious: text != previous)

            if state != controller.activityState {
                DispatchQueue.main.async {
                    controller.activityState = state
                    NotificationManager.shared.handleStateChange(controller: controller, state: state)
                }
            }

            // Update auto-title from Claude task / git branch (only on state changes
            // or periodically — use a counter to avoid running git too often)
            updateAutoTitle(controller: controller, text: text)
        }
    }

    // MARK: - State detection

    private func detectState(text: String, changedFromPrevious changed: Bool) -> PaneActivity {
        let lower = text.lowercased()

        // Waiting-for-input takes highest priority
        for pattern in Self.waitingPatterns {
            if lower.contains(pattern.lowercased()) {
                return .waitingForInput
            }
        }

        // Check whether the last non-empty line is a shell prompt
        let lastLine = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""

        for suffix in Self.idlePromptSuffixes {
            if lastLine.hasSuffix(suffix) || lastLine == suffix.trimmingCharacters(in: .whitespaces) {
                return .idle
            }
        }

        // Output was written since last poll → still executing
        if changed { return .executing }

        return .idle
    }

    // MARK: - Auto-title

    /// Polls counter so we run git (slow) less often than text scanning (fast).
    private var titlePollCount: [ObjectIdentifier: Int] = [:]
    private static let gitPollInterval = 10  // every 10 poll cycles (~15s)

    private func updateAutoTitle(controller: TerminalController, text: String) {
        let id = ObjectIdentifier(controller)
        let count = (titlePollCount[id] ?? 0) + 1
        titlePollCount[id] = count

        // Claude Code task title: check every cycle (cheap regex)
        if let task = WindowTitleExtractor.claudeTask(from: text) {
            DispatchQueue.main.async {
                controller.casperTitleHint = task
            }
            return
        }

        // Git context: run every `gitPollInterval` cycles to avoid hammering disk
        guard count % Self.gitPollInterval == 0 else { return }
        let cwd = controller.focusedSurface?.pwd
        DispatchQueue.global(qos: .utility).async {
            let git = cwd.flatMap { WindowTitleExtractor.gitContext(inDirectory: $0) }
            DispatchQueue.main.async {
                controller.casperTitleHint = git  // nil clears the hint
            }
        }
    }

    // MARK: - Text reader

    private func readLastLines(_ surface: Ghostty.SurfaceView, count: Int) -> String {
        guard let surf = surface.surface else { return "" }
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
        guard ghostty_surface_read_text(surf, sel, &text) else { return "" }
        defer { ghostty_surface_free_text(surf, &text) }
        let full = String(cString: text.text)
        let lines = full.components(separatedBy: "\n")
        return lines.suffix(count).joined(separator: "\n")
    }
}
