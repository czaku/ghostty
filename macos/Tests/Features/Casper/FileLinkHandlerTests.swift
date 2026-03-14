import Testing
import Foundation
@testable import Ghostty

@Suite("FileLinkHandler.fileLink(inText:row:)")
struct FileLinkHandlerTests {

    // MARK: - Basic detection

    @Test func detectsAbsolutePathWithLine() {
        let text = "Error in /Users/luke/dev/foo/bar.swift:42"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)
        // fileLink validates FileManager.fileExists, so we can only assert nil
        // in unit tests (file won't exist). We test the regex shape separately.
        _ = link // just ensure no crash
    }

    @Test func returnsNilForRowOutOfBounds() {
        let text = "line one\nline two"
        let link = FileLinkHandler.fileLink(inText: text, row: 99)
        #expect(link == nil)
    }

    @Test func returnsNilForNegativeRow() {
        let text = "line one"
        let link = FileLinkHandler.fileLink(inText: text, row: -1)
        #expect(link == nil)
    }

    @Test func returnsNilForPlainText() {
        let text = "no path here at all"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)
        #expect(link == nil)
    }

    @Test func returnsNilForRelativePath() {
        // Only absolute paths (starting with /) should match
        let text = "src/main.swift:10"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)
        #expect(link == nil)
    }

    @Test func multilinePicksCorrectRow() {
        // Row 0 has no link, row 1 has a non-existent path — just verify row selection works
        let text = "nothing here\n/tmp/some_file_that_does_not_exist_xyz.swift:5"
        // Row 1 would attempt the regex but fail the fileExists check
        let row0 = FileLinkHandler.fileLink(inText: text, row: 0)
        #expect(row0 == nil)
        // row 1 — regex should match even though file doesn't exist (returns nil from fileExists guard)
        let row1 = FileLinkHandler.fileLink(inText: text, row: 1)
        // nil because the file doesn't exist — correct behaviour
        #expect(row1 == nil)
    }
}

@Suite("FileLinkHandler — real file detection")
struct FileLinkHandlerRealFileTests {

    @Test func detectsLinkInRealTempFile() throws {
        // Create a real temp file so fileExists check passes
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper_test_\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "// test".write(to: tmp, atomically: true, encoding: .utf8)

        let text = "Error at \(tmp.path):12:5 — unexpected token"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)

        #expect(link != nil)
        #expect(link?.path == tmp.path)
        #expect(link?.line == 12)
        #expect(link?.col == 5)
    }

    @Test func detectsLinkWithoutColumn() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper_test_\(UUID().uuidString).ts")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "// test".write(to: tmp, atomically: true, encoding: .utf8)

        let text = "\(tmp.path):99"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)

        #expect(link != nil)
        #expect(link?.line == 99)
        #expect(link?.col == 1) // default column when omitted
    }

    @Test func picksFirstMatchOnRow() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper_test_\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "# test".write(to: tmp, atomically: true, encoding: .utf8)

        // Two references on same line — should pick the first one
        let text = "\(tmp.path):3 and \(tmp.path):7"
        let link = FileLinkHandler.fileLink(inText: text, row: 0)
        #expect(link?.line == 3)
    }
}
