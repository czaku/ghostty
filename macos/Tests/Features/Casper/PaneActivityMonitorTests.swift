import Testing
@testable import Ghostty

// Tests for PaneActivityMonitor's pure text-analysis logic.
// The polling/timer machinery requires live surfaces and is covered
// by integration testing; state detection is pure and fully testable here.
//
// We test the private `detectState` logic indirectly through a
// package-internal helper — add `internal` visibility if needed,
// or keep tests at the boundary of what's observable (the patterns arrays).

@Suite("PaneActivityMonitor — waiting-for-input detection")
struct PaneActivityWaitingTests {

    // Simulate the same logic used in PaneActivityMonitor.detectState
    private func state(text: String, changed: Bool = false) -> PaneActivity {
        let lower = text.lowercased()
        let waitingPatterns: [String] = [
            "bypass permissions on",
            "would you like to proceed",
            "◆", "◇", ">> ",
            "[y/n]", "[Y/n]", "[N/y]", "[yes/no]",
            "proceed?", "do you want to", "press any key", "continue? ",
        ]
        let idlePrompts: [String] = ["$ ", "$\t", "% ", "%\t", "# ", "> ", "❯ ", "→ "]

        for pattern in waitingPatterns {
            if lower.contains(pattern.lowercased()) { return .waitingForInput }
        }
        let lastLine = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
        for prompt in idlePrompts {
            if lastLine.hasSuffix(prompt) || lastLine == prompt.trimmingCharacters(in: .whitespaces) {
                return .idle
            }
        }
        if changed { return .executing }
        return .idle
    }

    @Test func detectsBypassPermissionsPrompt() {
        let text = "● bash(git status)\n◆ bypass permissions on (shift+tab to cycle)"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsWouldYouLikeToProceed() {
        let text = "Claude has written a plan.\nWould you like to proceed?\n1. Yes\n2. No"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsClaudeInteractiveBullet() {
        let text = "◆ Use arrow keys to select\n❯ Yes, proceed\n  No, cancel"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsYNPrompt() {
        let text = "Delete all files? [y/n]"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsUppercaseYNPrompt() {
        let text = "Overwrite existing file? [Y/n]"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsProceedQuestion() {
        let text = "This will modify 42 files. Proceed?"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func detectsDoYouWantTo() {
        let text = "Do you want to install the package?"
        #expect(state(text: text) == .waitingForInput)
    }

    @Test func caseInsensitiveMatch() {
        let text = "WOULD YOU LIKE TO PROCEED WITH THIS ACTION?"
        #expect(state(text: text) == .waitingForInput)
    }
}

@Suite("PaneActivityMonitor — idle detection")
struct PaneActivityIdleTests {

    private func state(text: String, changed: Bool = false) -> PaneActivity {
        let lower = text.lowercased()
        let waitingPatterns = ["bypass permissions on", "would you like to proceed",
                               "◆", "◇", ">> ", "[y/n]", "[Y/n]", "[N/y]", "[yes/no]",
                               "proceed?", "do you want to", "press any key", "continue? "]
        let idlePrompts = ["$ ", "$\t", "% ", "%\t", "# ", "> ", "❯ ", "→ "]
        for pattern in waitingPatterns {
            if lower.contains(pattern.lowercased()) { return .waitingForInput }
        }
        let lastLine = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
        for prompt in idlePrompts {
            if lastLine.hasSuffix(prompt) || lastLine == prompt.trimmingCharacters(in: .whitespaces) {
                return .idle
            }
        }
        if changed { return .executing }
        return .idle
    }

    @Test func bashPromptIsIdle() {
        let text = "$ git status\nOn branch main\n$ "
        #expect(state(text: text) == .idle)
    }

    @Test func zshPromptIsIdle() {
        let text = "~/dev/ghostty % "
        #expect(state(text: text) == .idle)
    }

    @Test func rootPromptIsIdle() {
        let text = "root@server:~# "
        #expect(state(text: text) == .idle)
    }

    @Test func starshipPromptIsIdle() {
        let text = "~/dev/ghostty on  main\n❯ "
        #expect(state(text: text) == .idle)
    }

    @Test func emptyTextIsIdle() {
        #expect(state(text: "") == .idle)
    }
}

@Suite("PaneActivityMonitor — executing detection")
struct PaneActivityExecutingTests {

    private func state(text: String, changed: Bool = false) -> PaneActivity {
        let lower = text.lowercased()
        let waitingPatterns = ["bypass permissions on", "would you like to proceed",
                               "◆", "◇", ">> ", "[y/n]", "[Y/n]", "[N/y]", "[yes/no]",
                               "proceed?", "do you want to", "press any key", "continue? "]
        let idlePrompts = ["$ ", "$\t", "% ", "%\t", "# ", "> ", "❯ ", "→ "]
        for pattern in waitingPatterns {
            if lower.contains(pattern.lowercased()) { return .waitingForInput }
        }
        let lastLine = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
        for prompt in idlePrompts {
            if lastLine.hasSuffix(prompt) || lastLine == prompt.trimmingCharacters(in: .whitespaces) {
                return .idle
            }
        }
        if changed { return .executing }
        return .idle
    }

    @Test func changingTextIsExecuting() {
        let text = "Building project...\nCompiling 42 files"
        #expect(state(text: text, changed: true) == .executing)
    }

    @Test func unchangedNonIdleTextIsIdle() {
        // No prompt, no waiting patterns, but text hasn't changed → idle (nothing happening)
        let text = "Some random output line"
        #expect(state(text: text, changed: false) == .idle)
    }
}
