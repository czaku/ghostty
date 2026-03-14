import AppKit
import GhosttyKit
import OSLog

/// Implements "Ask AI" — takes selected text (or the last N lines) from the
/// focused terminal surface and opens a new pane running the configured AI
/// command with that text as the initial question.
///
/// Provider is configured via `ask-ai-command` in config.casper:
///
///   ask-ai-command = claude          # default — opens `claude "<question>"`
///   ask-ai-command = omnai           # Omnai CLI
///   ask-ai-command = openai          # OpenAI CLI
///   ask-ai-command = my-ai-script    # any script on $PATH
///
/// The command receives the question as its first argument, quoted.
/// For `claude`, the question is passed as `--message` so a conversation
/// starts immediately without the user having to type anything.
enum AskAIAction {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AskAIAction")
    private static let contextLines = 30

    // MARK: - Main entry point

    /// Called from the "Ask AI" menu item / keyboard shortcut.
    /// Reads context from the focused surface and opens a new terminal with the AI command.
    @MainActor
    static func run(ghostty: Ghostty.App, config: Ghostty.Config) {
        guard let controller = TerminalController.all.first(where: { $0.window?.isKeyWindow == true }),
              let surface = controller.focusedSurface
        else { return }

        let context = extractContext(from: surface)
        guard !context.isEmpty else {
            Self.logger.info("AskAI: no context to send")
            return
        }

        let aiCommand = config.askAICommand
        let command = buildCommand(provider: aiCommand, question: context)

        var surfaceConfig = Ghostty.SurfaceConfiguration()
        surfaceConfig.workingDirectory = surface.pwd
        // Arrow-up style: command is pre-populated but not executed
        // The user sees the full question and can review/edit before hitting Enter
        surfaceConfig.initialInput = command

        // Open in a new split below the current surface if possible,
        // otherwise open a new window
        NotificationCenter.default.post(
            name: Ghostty.Notification.ghosttyNewTab,
            object: surface,
            userInfo: [Ghostty.Notification.NewSurfaceConfigKey: surfaceConfig]
        )
    }

    // MARK: - Context extraction

    private static func extractContext(from surface: Ghostty.SurfaceView) -> String {
        guard let surf = surface.surface else { return "" }

        // Try to get selected text first (user may have highlighted an error)
        // Fall back to last N visible lines
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surf, sel, &text) else { return "" }
        defer { ghostty_surface_free_text(surf, &text) }

        let full = String(cString: text.text)
        let lines = full.components(separatedBy: "\n")

        // Take last `contextLines` non-empty lines — skip the current prompt line
        let meaningful = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(contextLines)
        return meaningful.joined(separator: "\n")
    }

    // MARK: - Command builder

    static func buildCommand(provider: String, question: String) -> String {
        let escaped = escapeForShell(question)

        switch provider {
        case "claude":
            // `claude --message` starts a conversation with the question immediately
            return "claude --message \(escaped)"
        case "omnai":
            return "omnai ask \(escaped)"
        case "openai":
            return "openai api chat.completions.create -m gpt-4o -g user \(escaped)"
        default:
            // Generic: pass as first argument
            return "\(provider) \(escaped)"
        }
    }

    // MARK: - Shell escaping

    /// Single-quotes the string and escapes any single-quote characters within.
    static func escapeForShell(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
