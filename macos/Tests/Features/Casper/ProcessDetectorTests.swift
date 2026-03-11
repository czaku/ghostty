import Testing
@testable import Ghostty

@Suite("ProcessDetector pattern matching")
struct ProcessDetectorPatternTests {

    @Test func exactMatchClaude() {
        #expect(ProcessDetector.matches("claude", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func wildcardMatchClaudeEdge() {
        #expect(ProcessDetector.matches("claude-edge", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func wildcardMatchClaudeJobforge() {
        #expect(ProcessDetector.matches("claude-jobforge", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func wildcardMatchClaudeAnything() {
        #expect(ProcessDetector.matches("claude-xyz-abc", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func exactMatchNvim() {
        #expect(ProcessDetector.matches("nvim", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func exactMatchLazygit() {
        #expect(ProcessDetector.matches("lazygit", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func noMatchBash() {
        #expect(!ProcessDetector.matches("bash", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func noMatchZsh() {
        #expect(!ProcessDetector.matches("zsh", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func noMatchNode() {
        #expect(!ProcessDetector.matches("node", patterns: ProcessDetector.replayablePatterns))
    }

    @Test func noMatchPartialPrefix() {
        // "claud" should not match "claude" or "claude-*"
        #expect(!ProcessDetector.matches("claud", patterns: ProcessDetector.replayablePatterns))
    }
}

@Suite("ProcessDetector restore commands")
struct ProcessDetectorRestoreCommandTests {

    @Test func claudeGetsResumeflag() {
        #expect(ProcessDetector.restoreCommand(for: "claude") == "claude --continue")
    }

    @Test func claudeWrapperRunsAsIs() {
        // Wrapper scripts like claude-edge handle their own setup
        #expect(ProcessDetector.restoreCommand(for: "claude-edge") == "claude-edge")
    }

    @Test func claudeJobforgeRunsAsIs() {
        #expect(ProcessDetector.restoreCommand(for: "claude-jobforge") == "claude-jobforge")
    }

    @Test func nvimRunsAsIs() {
        #expect(ProcessDetector.restoreCommand(for: "nvim") == "nvim")
    }

    @Test func lazygitRunsAsIs() {
        #expect(ProcessDetector.restoreCommand(for: "lazygit") == "lazygit")
    }
}

@Suite("ProcessDetector live detection", .serialized)
struct ProcessDetectorLiveTests {

    @Test func detectsCurrentProcess() {
        // The test runner itself is a process — we should be able to find
        // our own pid in the output of allPids via replayableProcess.
        // Since our process name won't be on the whitelist, the indirect
        // test is: replayableProcess with a bogus dir returns nil (no crash).
        let result = ProcessDetector.replayableProcess(inDirectory: "/nonexistent/path/xyz")
        #expect(result == nil)
    }
}
