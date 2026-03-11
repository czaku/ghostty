import Testing
@testable import Ghostty

@Suite("CasperClipboard.stripped")
struct CasperClipboardTests {

    // MARK: - Should strip

    @Test func stripsBasicBashFence() {
        let input = "```bash\necho hello\n```"
        #expect(CasperClipboard.stripped(input) == "echo hello")
    }

    @Test func stripsUnlabelledFence() {
        let input = "```\nls -la\n```"
        #expect(CasperClipboard.stripped(input) == "ls -la")
    }

    @Test func stripsMultiLineFence() {
        let input = "```sh\ncd ~/dev/edge\nnpm install\nnpm run dev\n```"
        let expected = "cd ~/dev/edge\nnpm install\nnpm run dev"
        #expect(CasperClipboard.stripped(input) == expected)
    }

    @Test func stripsTrailingNewlineBeforeFence() {
        // Claude often adds a trailing newline after the closing fence
        let input = "```bash\necho hi\n```\n"
        #expect(CasperClipboard.stripped(input) == "echo hi")
    }

    @Test func stripsPythonFence() {
        let input = "```python\nprint('hello')\n```"
        #expect(CasperClipboard.stripped(input) == "print('hello')")
    }

    // MARK: - Should not strip

    @Test func returnsNilForPlainText() {
        #expect(CasperClipboard.stripped("just a plain command") == nil)
    }

    @Test func returnsNilForPartialFence() {
        // Opening fence but no closing fence
        #expect(CasperClipboard.stripped("```bash\necho hi") == nil)
    }

    @Test func returnsNilForSingleLine() {
        #expect(CasperClipboard.stripped("```bash```") == nil)
    }

    @Test func returnsNilForEmpty() {
        #expect(CasperClipboard.stripped("") == nil)
    }

    @Test func doesNotStripMiddleFence() {
        // Fenced block that isn't the whole content
        let input = "Here is the command:\n```bash\necho hi\n```\nRun it."
        #expect(CasperClipboard.stripped(input) == nil)
    }

    @Test func doesNotStripInlineCode() {
        #expect(CasperClipboard.stripped("`echo hi`") == nil)
    }
}
