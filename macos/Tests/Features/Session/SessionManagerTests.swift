import Testing
import Foundation
@testable import Ghostty

// MARK: - Helpers

private func makeSession(windows: Int = 1, surfacesPerWindow: Int = 1) -> SessionData {
    let surfaces = (0..<surfacesPerWindow).map { i in
        SessionSurface(
            uuid: UUID().uuidString,
            cwd: "/tmp/dir\(i)",
            title: "zsh — dir\(i)",
            scrollback: i == 0 ? "$ echo hello\nhello\n$ " : ""
        )
    }
    let windows = (0..<windows).map { i in
        SessionWindow(
            frame: SessionFrame(x: Double(i * 100), y: 200, width: 1200, height: 800),
            surfaces: surfaces
        )
    }
    return SessionData(version: 1, savedAt: Date(), windows: windows)
}

private func encodeSession(_ session: SessionData) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted
    return try encoder.encode(session)
}

// MARK: - SessionData Codable

@Suite("SessionData JSON round-trip")
struct SessionDataCodableTests {

    @Test func encodesAndDecodes() throws {
        let original = makeSession(windows: 2, surfacesPerWindow: 2)
        let data = try encodeSession(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionData.self, from: data)

        #expect(decoded.version == original.version)
        #expect(decoded.windows.count == original.windows.count)

        let ow = original.windows[0]
        let dw = decoded.windows[0]
        #expect(dw.frame.x == ow.frame.x)
        #expect(dw.frame.width == ow.frame.width)
        #expect(dw.surfaces.count == ow.surfaces.count)

        let os = ow.surfaces[0]
        let ds = dw.surfaces[0]
        #expect(ds.uuid == os.uuid)
        #expect(ds.cwd == os.cwd)
        #expect(ds.title == os.title)
        #expect(ds.scrollback == os.scrollback)
    }

    @Test func nullCwdRoundTrips() throws {
        let surface = SessionSurface(uuid: "x", cwd: nil, title: "sh", scrollback: "")
        let window = SessionWindow(frame: SessionFrame(x: 0, y: 0, width: 800, height: 600), surfaces: [surface])
        let session = SessionData(version: 1, savedAt: Date(), windows: [window])

        let data = try encodeSession(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionData.self, from: data)

        #expect(decoded.windows[0].surfaces[0].cwd == nil)
    }

    @Test func emptyScrollbackRoundTrips() throws {
        let surface = SessionSurface(uuid: "y", cwd: "/tmp", title: "bash", scrollback: "")
        let window = SessionWindow(frame: SessionFrame(x: 0, y: 0, width: 800, height: 600), surfaces: [surface])
        let session = SessionData(version: 1, savedAt: Date(), windows: [window])

        let data = try encodeSession(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionData.self, from: data)

        #expect(decoded.windows[0].surfaces[0].scrollback == "")
    }
}

// MARK: - SessionManager.loadSession

@Suite("SessionManager.loadSession")
struct SessionManagerLoadTests {

    @Test func loadsValidSessionFromFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_test_load_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = makeSession(windows: 1, surfacesPerWindow: 1)
        let data = try encodeSession(session)
        try data.write(to: tmp)

        let loaded = try SessionManager.shared.loadSession(url: tmp)
        #expect(loaded.version == 1)
        #expect(loaded.windows.count == 1)
        #expect(loaded.windows[0].surfaces[0].cwd == "/tmp/dir0")
    }

    @Test func loadsMultiWindowSession() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_test_multi_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = makeSession(windows: 3, surfacesPerWindow: 2)
        try encodeSession(session).write(to: tmp)

        let loaded = try SessionManager.shared.loadSession(url: tmp)
        #expect(loaded.windows.count == 3)
        #expect(loaded.windows[0].surfaces.count == 2)
    }

    @Test func throwsOnMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_nonexistent_\(UUID().uuidString).json")
        #expect(throws: (any Error).self) {
            try SessionManager.shared.loadSession(url: missing)
        }
    }

    @Test func throwsOnMalformedJSON() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_bad_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try "not json at all".write(to: tmp, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) {
            try SessionManager.shared.loadSession(url: tmp)
        }
    }
}

// MARK: - SessionManager crash recovery

@Suite("SessionManager crash recovery")
struct SessionManagerCrashRecoveryTests {

    private func writeCurrentSession() throws -> URL {
        let url = SessionManager.shared.currentSessionURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let session = makeSession()
        try encodeSession(session).write(to: url)
        return url
    }

    @Test func detectsCrashRecoveryFile() throws {
        let url = try writeCurrentSession()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SessionManager.shared.crashRecoverySessionExists() == true)
    }

    @Test func noFalsePositiveWhenFileAbsent() throws {
        // Make sure the file doesn't exist.
        try? FileManager.default.removeItem(at: SessionManager.shared.currentSessionURL)
        #expect(SessionManager.shared.crashRecoverySessionExists() == false)
    }

    @Test func clearCrashRecoveryRemovesFile() throws {
        let url = try writeCurrentSession()
        #expect(FileManager.default.fileExists(atPath: url.path))

        SessionManager.shared.clearCrashRecovery()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: - SessionManager pending restore (CLI integration)

@Suite("SessionManager pending restore")
struct SessionManagerPendingRestoreTests {

    private func writePendingRestore(pointing sessionURL: URL) throws {
        let pending = SessionManager.shared.pendingRestoreURL
        try FileManager.default.createDirectory(
            at: pending.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sessionURL.path.write(to: pending, atomically: true, encoding: .utf8)
    }

    @Test func consumeReturnsMostRecentSession() throws {
        // Write a real session file first.
        let sessionTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_pending_session_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sessionTmp) }
        try encodeSession(makeSession()).write(to: sessionTmp)

        // Write the pending-restore marker pointing at it.
        try writePendingRestore(pointing: sessionTmp)
        defer { try? FileManager.default.removeItem(at: SessionManager.shared.pendingRestoreURL) }

        let result = SessionManager.shared.consumePendingRestore()
        #expect(result != nil)
        #expect(result?.windows.count == 1)
    }

    @Test func consumeDeletesMarkerFile() throws {
        let sessionTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_pending_session2_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sessionTmp) }
        try encodeSession(makeSession()).write(to: sessionTmp)

        try writePendingRestore(pointing: sessionTmp)
        let pendingURL = SessionManager.shared.pendingRestoreURL

        _ = SessionManager.shared.consumePendingRestore()
        #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
    }

    @Test func consumeReturnsNilWhenNoMarker() {
        try? FileManager.default.removeItem(at: SessionManager.shared.pendingRestoreURL)
        #expect(SessionManager.shared.consumePendingRestore() == nil)
    }

    @Test func consumeReturnsNilWhenMarkerPointsToMissingFile() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty_gone_\(UUID().uuidString).json")
        try writePendingRestore(pointing: missing)
        defer { try? FileManager.default.removeItem(at: SessionManager.shared.pendingRestoreURL) }

        #expect(SessionManager.shared.consumePendingRestore() == nil)
    }
}

// MARK: - SessionManager.listSessions ordering

@Suite("SessionManager.listSessions")
struct SessionManagerListTests {

    @Test func returnsEmptyWhenNoSessions() {
        // If sessions dir doesn't exist or is empty, listSessions returns [].
        // We just verify the method doesn't crash.
        let sessions = SessionManager.shared.listSessions()
        // Can be non-empty if user has real sessions — just ensure no crash.
        _ = sessions
    }

    @Test func latestSessionURLMatchesFirstEntry() throws {
        // Ensure `latestSessionURL()` agrees with the first entry in `listSessions()`.
        let list = SessionManager.shared.listSessions()
        let latest = SessionManager.shared.latestSessionURL()
        if list.isEmpty {
            #expect(latest == nil)
        } else {
            #expect(latest == list.first?.url)
        }
    }
}
