import AppKit
import OSLog

/// Casper-specific clipboard helpers for the vibe coding workflow.
enum CasperClipboard {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CasperClipboard")

    // MARK: - Strip code fences

    /// If the current general pasteboard contains a fenced code block
    /// (e.g. text from Claude or ChatGPT), strips the fences in-place
    /// so the raw command is pasted instead.
    ///
    /// Handles:
    ///   ```bash\ncommand\n```   →  command
    ///   ```\ncommand\n```       →  command
    ///   Multi-line blocks are preserved, only the fence lines are removed.
    ///
    /// Returns true if the pasteboard was modified.
    @discardableResult
    static func stripCodeFencesIfNeeded() -> Bool {
        let pb = NSPasteboard.general
        guard let original = pb.string(forType: .string) else { return false }
        guard let stripped = stripped(original), stripped != original else { return false }
        pb.clearContents()
        pb.setString(stripped, forType: .string)
        logger.debug("Stripped code fences from pasteboard")
        return true
    }

    /// Returns the inner content of a fenced code block, or nil if the
    /// string is not a code fence.
    static func stripped(_ text: String) -> String? {
        var lines = text.components(separatedBy: "\n")

        // Allow a single trailing newline — don't count it as a content line.
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 2 else { return nil }

        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let last  = lines[lines.count - 1].trimmingCharacters(in: .whitespaces)

        guard first.hasPrefix("```"), last == "```" else { return nil }

        // Drop the opening and closing fence lines.
        let inner = lines.dropFirst().dropLast().joined(separator: "\n")
        return inner
    }

    // MARK: - Copy as markdown

    /// Wraps the given text in a fenced markdown code block and writes it
    /// to the general pasteboard. Pass the current terminal selection.
    static func copyAsMarkdown(_ text: String) {
        guard !text.isEmpty else { return }
        let wrapped = "```\n\(text)\n```"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(wrapped, forType: .string)
        logger.debug("Copied selection as markdown code block (\(text.count) chars)")
    }
}
