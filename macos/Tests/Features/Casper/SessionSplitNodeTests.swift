import Testing
import Foundation
@testable import Ghostty

@Suite("SessionSplitNode Codable")
struct SessionSplitNodeCodableTests {

    private func roundTrip(_ node: SessionSplitNode) throws -> SessionSplitNode {
        let data = try JSONEncoder().encode(node)
        return try JSONDecoder().decode(SessionSplitNode.self, from: data)
    }

    @Test func leafRoundTrips() throws {
        let surface = SessionSurface(uuid: "abc-123", cwd: "/tmp", title: "zsh", scrollback: "$ ls\n")
        let node = SessionSplitNode.leaf(surface)
        let decoded = try roundTrip(node)
        if case .leaf(let s) = decoded {
            #expect(s.uuid == "abc-123")
            #expect(s.cwd == "/tmp")
            #expect(s.scrollback == "$ ls\n")
        } else {
            Issue.record("Expected .leaf after round-trip")
        }
    }

    @Test func horizontalSplitRoundTrips() throws {
        let left = SessionSplitNode.leaf(SessionSurface(uuid: "L", cwd: "/a", title: "L", scrollback: ""))
        let right = SessionSplitNode.leaf(SessionSurface(uuid: "R", cwd: "/b", title: "R", scrollback: ""))
        let split = SessionSplitNode.split(direction: .horizontal, ratio: 0.4, left: left, right: right)
        let decoded = try roundTrip(split)
        if case .split(let dir, let ratio, let dl, let dr) = decoded {
            #expect(dir == .horizontal)
            #expect(abs(ratio - 0.4) < 0.0001)
            if case .leaf(let s) = dl { #expect(s.uuid == "L") } else { Issue.record("Expected leaf") }
            if case .leaf(let s) = dr { #expect(s.uuid == "R") } else { Issue.record("Expected leaf") }
        } else {
            Issue.record("Expected .split after round-trip")
        }
    }

    @Test func verticalSplitRoundTrips() throws {
        let left = SessionSplitNode.leaf(SessionSurface(uuid: "T", cwd: "/t", title: "top", scrollback: ""))
        let right = SessionSplitNode.leaf(SessionSurface(uuid: "B", cwd: "/b", title: "bot", scrollback: ""))
        let split = SessionSplitNode.split(direction: .vertical, ratio: 0.6, left: left, right: right)
        let decoded = try roundTrip(split)
        if case .split(let dir, _, _, _) = decoded {
            #expect(dir == .vertical)
        } else {
            Issue.record("Expected .split after round-trip")
        }
    }

    @Test func nestedSplitRoundTrips() throws {
        let a = SessionSplitNode.leaf(SessionSurface(uuid: "A", cwd: "/a", title: "A", scrollback: ""))
        let b = SessionSplitNode.leaf(SessionSurface(uuid: "B", cwd: "/b", title: "B", scrollback: ""))
        let c = SessionSplitNode.leaf(SessionSurface(uuid: "C", cwd: "/c", title: "C", scrollback: ""))
        let inner = SessionSplitNode.split(direction: .horizontal, ratio: 0.5, left: a, right: b)
        let outer = SessionSplitNode.split(direction: .vertical, ratio: 0.3, left: inner, right: c)
        let decoded = try roundTrip(outer)
        #expect(decoded.surfaces.count == 3)
        let uuids = Set(decoded.surfaces.map(\.uuid))
        #expect(uuids == ["A", "B", "C"])
    }

    @Test func surfacesPropertyReturnsAllLeaves() {
        let a = SessionSplitNode.leaf(SessionSurface(uuid: "A", cwd: nil, title: "A", scrollback: ""))
        let b = SessionSplitNode.leaf(SessionSurface(uuid: "B", cwd: nil, title: "B", scrollback: ""))
        let c = SessionSplitNode.leaf(SessionSurface(uuid: "C", cwd: nil, title: "C", scrollback: ""))
        let inner = SessionSplitNode.split(direction: .horizontal, ratio: 0.5, left: a, right: b)
        let root = SessionSplitNode.split(direction: .vertical, ratio: 0.5, left: inner, right: c)
        #expect(root.surfaces.count == 3)
        #expect(root.surfaces[0].uuid == "A")
        #expect(root.surfaces[1].uuid == "B")
        #expect(root.surfaces[2].uuid == "C")
    }

    @Test func leafSurfacesReturnsOneEntry() {
        let node = SessionSplitNode.leaf(SessionSurface(uuid: "X", cwd: nil, title: "X", scrollback: ""))
        #expect(node.surfaces.count == 1)
        #expect(node.surfaces[0].uuid == "X")
    }
}
