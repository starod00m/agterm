import Foundation
import Testing
@testable import agtermCore

@MainActor
struct SidebarNumberingTests {
    @Test func treeNumbersWorkspacesInOrderAndSessionsFromOneInEach() throws {
        let store = makeStore()
        let workspaces = (1 ... 3).map { store.addWorkspace(name: "ws\($0)") }
        var sessions: [[Session]] = []
        for workspace in workspaces {
            sessions.append(try (0 ..< 2).map { _ in try #require(store.addSession(toWorkspace: workspace.id, cwd: "/")) })
        }

        #expect(workspaces.map { SidebarNumbering.position(ofWorkspace: $0.id, in: store, flaggedLayout: .flat) } == [1, 2, 3])
        for row in sessions {
            #expect(row.map { SidebarNumbering.position(ofSession: $0.id, in: store, flaggedLayout: .flat) } == [1, 2])
        }
    }

    @Test func focusFilterNumbersOnlyTheVisibleMembers() throws {
        let store = makeStore()
        let first = store.addWorkspace(name: "first")
        let hidden = store.addWorkspace(name: "hidden")
        let third = store.addWorkspace(name: "third")
        let hiddenSession = try #require(store.addSession(toWorkspace: hidden.id, cwd: "/"))
        let thirdSession = try #require(store.addSession(toWorkspace: third.id, cwd: "/"))
        store.setFocusMembership(first.id, member: true)
        store.setFocusMembership(third.id, member: true)
        store.setFocusEnabled(true)

        #expect(SidebarNumbering.position(ofWorkspace: first.id, in: store, flaggedLayout: .flat) == 1)
        #expect(SidebarNumbering.position(ofWorkspace: hidden.id, in: store, flaggedLayout: .flat) == nil)
        #expect(SidebarNumbering.position(ofWorkspace: third.id, in: store, flaggedLayout: .flat) == 2)
        #expect(SidebarNumbering.position(ofSession: hiddenSession.id, in: store, flaggedLayout: .flat) == nil)
        #expect(SidebarNumbering.position(ofSession: thirdSession.id, in: store, flaggedLayout: .flat) == 1)
    }

    @Test func aMarkedSetWithTheFilterOffKeepsTreeNumbering() {
        let store = makeStore()
        let workspaces = (1 ... 3).map { store.addWorkspace(name: "ws\($0)") }
        store.setFocusMembership(workspaces[2].id, member: true)

        #expect(workspaces.map { SidebarNumbering.position(ofWorkspace: $0.id, in: store, flaggedLayout: .flat) } == [1, 2, 3])
    }

    @Test func theTenthRowDrawsZeroAndLaterRowsTheStub() throws {
        let store = makeStore()
        let workspace = store.addWorkspace(name: "big")
        let sessions = try (0 ..< 12).map { _ in try #require(store.addSession(toWorkspace: workspace.id, cwd: "/")) }

        let symbols = sessions.map { SidebarNumbering.symbolName(forPosition: SidebarNumbering.position(ofSession: $0.id, in: store, flaggedLayout: .flat)) }
        #expect(symbols[0] == "1.circle")
        #expect(symbols[8] == "9.circle")
        #expect(symbols[9] == "0.circle")
        #expect(symbols[10] == "circle.dashed")
        #expect(symbols[11] == "circle.dashed")
    }

    @Test func flaggedTreeNumbersOnlyFlaggedRowsAndIgnoresTheFocusFilter() throws {
        let store = makeStore()
        let first = store.addWorkspace(name: "first")
        let unflagged = store.addWorkspace(name: "unflagged")
        let third = store.addWorkspace(name: "third")
        let plain = try #require(store.addSession(toWorkspace: first.id, cwd: "/"))
        let firstFlagged = try #require(store.addSession(toWorkspace: first.id, cwd: "/"))
        let unflaggedSession = try #require(store.addSession(toWorkspace: unflagged.id, cwd: "/"))
        let thirdFlagged = try (0 ..< 2).map { _ in try #require(store.addSession(toWorkspace: third.id, cwd: "/")) }
        for session in [firstFlagged] + thirdFlagged { session.flagged = true }
        store.setFocusMembership(unflagged.id, member: true)
        store.setFocusEnabled(true)
        store.setSidebarMode(.flagged)

        #expect([first, unflagged, third].map { SidebarNumbering.position(ofWorkspace: $0.id, in: store, flaggedLayout: .tree) } == [1, nil, 2])
        #expect([plain, firstFlagged, unflaggedSession].map { SidebarNumbering.position(ofSession: $0.id, in: store, flaggedLayout: .tree) } == [nil, 1, nil])
        #expect(thirdFlagged.map { SidebarNumbering.position(ofSession: $0.id, in: store, flaggedLayout: .tree) } == [1, 2])
    }

    @Test func flatFlaggedNumbersSessionsAcrossWorkspacesAndNoWorkspaceRow() throws {
        let store = makeStore()
        let first = store.addWorkspace(name: "first")
        let second = store.addWorkspace(name: "second")
        let plain = try #require(store.addSession(toWorkspace: first.id, cwd: "/"))
        let firstFlagged = try #require(store.addSession(toWorkspace: first.id, cwd: "/"))
        let secondFlagged = try (0 ..< 10).map { _ in try #require(store.addSession(toWorkspace: second.id, cwd: "/")) }
        for session in [firstFlagged] + secondFlagged { session.flagged = true }
        store.setSidebarMode(.flagged)

        #expect([first, second].map { SidebarNumbering.position(ofWorkspace: $0.id, in: store, flaggedLayout: .flat) } == [nil, nil])
        #expect(SidebarNumbering.position(ofSession: plain.id, in: store, flaggedLayout: .flat) == nil)
        #expect(SidebarNumbering.position(ofSession: firstFlagged.id, in: store, flaggedLayout: .flat) == 1)
        let positions = secondFlagged.map { SidebarNumbering.position(ofSession: $0.id, in: store, flaggedLayout: .flat) }
        #expect(positions == Array(2 ... 11))
        #expect(positions.suffix(2).map(SidebarNumbering.symbolName(forPosition:)) == ["0.circle", "circle.dashed"])
        #expect(SidebarNumbering.symbolName(forPosition: nil) == "circle.dashed")
    }
}
