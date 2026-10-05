import AppKit
import XCTest
@testable import agterm
import agtermCore

/// Hosted coverage for the sidebar row's name tooltip: it appears only while the label is too narrow to
/// show the whole name, and clears again once the name fits.
@MainActor
final class SidebarRowViewsTests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var actions: AppActions!
    private var window: NSWindow!
    private var scroll: NSScrollView!
    private var outline: SidebarOutlineView!
    private var coordinator: WorkspaceSidebar.Coordinator!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("agterm-row-views-tests-\(UUID().uuidString)", isDirectory: true)
            library = WindowLibrary(directory: stateDir)
            actions = AppActions(library: library)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            window?.orderOut(nil)
            window = nil
            scroll = nil
            outline = nil
            coordinator = nil
            actions = nil
            library = nil
            try? FileManager.default.removeItem(at: stateDir)
            stateDir = nil
        }
        try await super.tearDown()
    }

    func testATruncatedNameGetsTheFullNameAsItsTooltip() throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        buildSidebar(for: store)

        let name = "PROJ-123 enforce the storage quota on the plan endpoint before the billing cutover"
        store.renameSession(session.id, to: name)
        coordinator.reconcile()

        let field = try renderedNameField(forSession: session.id)
        XCTAssertEqual(field.toolTip, name,
                       "a name the row cannot show needs a hover reveal; the label truncates with no other way to read it")
    }

    func testANameThatFitsGetsNoTooltip() throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        buildSidebar(for: store)

        store.renameSession(session.id, to: "api")
        coordinator.reconcile()

        let field = try renderedNameField(forSession: session.id)
        XCTAssertNil(field.toolTip, "a fully visible name needs no tooltip; repeating it on hover is noise")
    }

    func testATitleTickRefreshesTheTooltipOnTheLiveCell() throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        buildSidebar(for: store)
        let cell = try renderedCell(forSession: session.id)
        let long = "PROJ-123 enforce the storage quota on the plan endpoint before the billing cutover"

        for (title, expected) in [("api", nil), (long, long), ("api", nil)] {
            session.oscTitle = title
            coordinator.reconcile()
            cell.layoutSubtreeIfNeeded()
            XCTAssertTrue(try renderedCell(forSession: session.id) === cell, "a title tick must keep the cell")
            XCTAssertEqual(cell.textField?.stringValue, title)
            XCTAssertEqual(cell.textField?.toolTip, expected, "the relabel must schedule the layout pass that owns the tooltip")
        }
    }

    func testWideningTheRowClearsAToolTipItNoLongerNeeds() throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        buildSidebar(for: store)

        store.renameSession(session.id, to: "PROJ-123 enforce the storage quota on the plan endpoint")
        coordinator.reconcile()
        let narrow = try renderedNameField(forSession: session.id)
        XCTAssertNotNil(narrow.toolTip, "the narrow sidebar should truncate this name")
        let narrowWidth = narrow.bounds.width

        setSidebarWidth(CGFloat(AppStore.sidebarWidthMax))

        let field = try renderedNameField(forSession: session.id)
        XCTAssertGreaterThan(field.bounds.width, narrowWidth,
                             "the row must widen here, or the tooltip assertion below proves nothing")
        XCTAssertNil(field.toolTip, "dragging the divider wider must re-evaluate, or a stale tooltip lingers")
    }

    func testRowsShowTheirVisiblePositionGlyph() throws {
        let store = try XCTUnwrap(library.activeStore)
        let first = store.workspaces[0]
        let firstSession = try XCTUnwrap(first.sessions.first)
        let second = store.addWorkspace(name: "second")
        let sessions = try (0..<3).map { _ in try XCTUnwrap(store.addSession(toWorkspace: second.id, cwd: "/a")) }
        buildSidebar(for: store)

        XCTAssertEqual(try renderedIcon(forRow: first.id), coordinator.rowIcon(forPosition: 1))
        XCTAssertEqual(try renderedIcon(forRow: second.id), coordinator.rowIcon(forPosition: 2))
        XCTAssertEqual(try renderedIcon(forRow: firstSession.id), coordinator.rowIcon(forPosition: 1))
        XCTAssertEqual(try renderedIcon(forRow: sessions[0].id), coordinator.rowIcon(forPosition: 1))
        XCTAssertEqual(try renderedIcon(forRow: sessions[2].id), coordinator.rowIcon(forPosition: 3))
    }

    func testClosingASessionRenumbersTheRowsBelowIt() throws {
        let store = try XCTUnwrap(library.activeStore)
        let workspace = store.workspaces[0]
        let added = try (0..<2).map { _ in try XCTUnwrap(store.addSession(toWorkspace: workspace.id, cwd: "/a")) }
        let closed = try XCTUnwrap(workspace.sessions.first)
        buildSidebar(for: store)
        XCTAssertEqual(try renderedIcon(forRow: added[1].id), coordinator.rowIcon(forPosition: 3))

        store.closeSession(closed.id)
        coordinator.reconcile()

        XCTAssertEqual(try renderedIcon(forRow: added[0].id), coordinator.rowIcon(forPosition: 1))
        XCTAssertEqual(try renderedIcon(forRow: added[1].id), coordinator.rowIcon(forPosition: 2))
    }

    func testMarkingAWorkspaceBrightensItAndItsSessionsWithTheFilterOffUntilUnmarked() throws {
        let store = try XCTUnwrap(library.activeStore)
        let marked = store.workspaces[0]
        let selected = try XCTUnwrap(marked.sessions.first)
        let sibling = try XCTUnwrap(store.addSession(toWorkspace: marked.id, cwd: "/a", select: false))
        let other = store.addWorkspace(name: "other")
        let outside = try XCTUnwrap(store.addSession(toWorkspace: other.id, cwd: "/a", select: false))
        store.setFlag(true, forSession: sibling.id)
        store.selectSession(selected.id)
        buildSidebar(for: store)
        coordinator.syncSelection()

        XCTAssertEqual(try glyphAlpha(forRow: selected.id), 0.85, accuracy: 0.001)
        for id in [marked.id, sibling.id, other.id, outside.id] {
            XCTAssertEqual(try glyphAlpha(forRow: id), 0.6, accuracy: 0.001)
        }

        store.setFocusMembership(marked.id, member: true)
        XCTAssertFalse(store.focusEnabled)
        coordinator.reconcile()
        coordinator.refreshSelectionAppearance()

        for id in [marked.id, selected.id, sibling.id] {
            XCTAssertEqual(try glyphAlpha(forRow: id), 1, accuracy: 0.001)
        }
        for id in [other.id, outside.id] {
            XCTAssertEqual(try glyphAlpha(forRow: id), 0.6, accuracy: 0.001)
        }
        XCTAssertEqual(try renderedIcon(forRow: sibling.id), coordinator.rowIcon(forPosition: 2, flagged: true))
        XCTAssertEqual(try renderedIcon(forRow: selected.id), coordinator.rowIcon(forPosition: 1))

        store.setFocusMembership(marked.id, member: false)
        coordinator.reconcile()
        coordinator.refreshSelectionAppearance()

        XCTAssertEqual(try glyphAlpha(forRow: selected.id), 0.85, accuracy: 0.001)
        for id in [marked.id, sibling.id] {
            XCTAssertEqual(try glyphAlpha(forRow: id), 0.6, accuracy: 0.001)
        }
    }

    func testAFlagFillsTheGlyphAndUnflaggingRestoresTheOutline() throws {
        let store = try XCTUnwrap(library.activeStore)
        let workspace = store.workspaces[0]
        let session = try XCTUnwrap(store.addSession(toWorkspace: workspace.id, cwd: "/a"))
        buildSidebar(for: store)

        store.setFlag(true, forSession: session.id)
        coordinator.reconcile()
        XCTAssertEqual(try renderedIcon(forRow: session.id), coordinator.rowIcon(forPosition: 2, flagged: true))
        XCTAssertEqual(try renderedIcon(forRow: workspace.id), coordinator.rowIcon(forPosition: 1))

        store.setFlag(false, forSession: session.id)
        coordinator.reconcile()
        XCTAssertEqual(try renderedIcon(forRow: session.id), coordinator.rowIcon(forPosition: 2))
    }

    func testTheStubStaysDimWhenFlaggedMarkedAndSelected() throws {
        let store = try XCTUnwrap(library.activeStore)
        let workspace = store.workspaces[0]
        let added = try (0..<10).map { _ in try XCTUnwrap(store.addSession(toWorkspace: workspace.id, cwd: "/a", select: false)) }
        let eleventh = try XCTUnwrap(added.last)
        store.setFlag(true, forSession: eleventh.id)
        store.setFocusMembership(workspace.id, member: true)
        store.selectSession(eleventh.id)
        buildSidebar(for: store)
        coordinator.syncSelection()
        coordinator.refreshSelectionAppearance()

        XCTAssertEqual(try renderedIcon(forRow: eleventh.id), coordinator.rowIcon(forPosition: nil))
        XCTAssertEqual(try glyphAlpha(forRow: eleventh.id), 0.4, accuracy: 0.001)
    }

    func testFlaggedRenameRestoresTheLabelAfterAnUnchangedCustomName() async throws {
        try await checkFlaggedRename(customName: "api", edited: "api", expected: "api")
    }

    func testFlaggedRenameRestoresTheLabelAfterAcceptingTheAutomaticName() async throws {
        try await checkFlaggedRename(customName: nil, edited: "automatic", expected: "automatic")
    }

    func testFlaggedRenameRendersTheNormalizedCommittedName() async throws {
        try await checkFlaggedRename(customName: "api", edited: "  worker  ", expected: "worker")
    }

    func testFlaggedRenameCancellationRestoresTheLabel() async throws {
        try await checkFlaggedRename(customName: "api", edited: "discarded", expected: "api", cancelled: true)
    }

    func testRejectedBlankWorkspaceRenameRestoresTheLabel() async throws {
        let store = try XCTUnwrap(library.activeStore)
        buildSidebar(for: store)
        let workspace = store.workspaces[0]
        let node = try XCTUnwrap(coordinator.workspaceNode(forID: workspace.id))
        let field = try beginRename(node)
        field.stringValue = "   "
        try endRename(field)
        await drainRenameCallback()
        let row = outline.row(forItem: node)
        let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, workspace.name)
        XCTAssertEqual(store.workspaces[0].name, workspace.name)
    }

    func testRenameCallbackDoesNotReloadAnEditStartedBeforeItRuns() async throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        buildSidebar(for: store)
        let node = try sessionNode(session.id)
        let field = try beginRename(node)
        try endRename(field)
        let nextField = try beginRename(node)
        nextField.stringValue = "unfinished"
        await drainRenameCallback()
        XCTAssertTrue(coordinator.renameController.isEditing)
        XCTAssertTrue(try renderedNameField(forSession: session.id) === nextField)
        XCTAssertEqual(nextField.stringValue, "unfinished")
        try endRename(nextField, cancelled: true)
        await drainRenameCallback()
    }

    private func checkFlaggedRename(customName: String?, edited: String, expected: String, cancelled: Bool = false) async throws {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.activeSession)
        session.oscTitle = "automatic"
        session.customName = customName
        session.flagged = true
        store.sidebarMode = .flagged
        let other = try XCTUnwrap(store.addSession(toWorkspace: store.workspaces[0].id, cwd: "/other"))
        other.flagged = true
        buildSidebar(for: store)
        let field = try beginRename(sessionNode(session.id))
        XCTAssertEqual(field.stringValue, customName ?? "automatic")
        field.stringValue = edited
        try endRename(field, cancelled: cancelled)
        store.selectSession(other.id)
        await drainRenameCallback()
        let restored = try renderedNameField(forSession: session.id)
        XCTAssertEqual(restored.stringValue, "\(expected) : \(store.workspaces[0].name)")
        XCTAssertEqual(session.customName, expected)
        XCTAssertFalse(restored.isEditable)
        XCTAssertEqual(restored.accessibilityIdentifier(), "session-row")
    }

    private func sessionNode(_ id: UUID) throws -> SidebarNode {
        try XCTUnwrap((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarNode }
            .first { $0.kind == .session && $0.id == id })
    }

    private func beginRename(_ node: SidebarNode) throws -> NSTextField {
        coordinator.renameController.beginEditing(node: node)
        let cell = try XCTUnwrap(outline.view(atColumn: 0, row: outline.row(forItem: node), makeIfNecessary: true) as? NSTableCellView)
        return try XCTUnwrap(cell.textField)
    }

    private func endRename(_ field: NSTextField, cancelled: Bool = false) throws {
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = field.stringValue
        if cancelled {
            XCTAssertTrue(coordinator.renameController.control(field, textView: editor,
                doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        } else {
            XCTAssertTrue(field.window?.makeFirstResponder(nil) == true)
        }
    }

    private func drainRenameCallback() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func buildSidebar(for store: AppStore) {
        outline = SidebarOutlineView()
        coordinator = WorkspaceSidebar.Coordinator(store: store, actions: actions)
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.headerView = nil
        outline.rowSizeStyle = .custom
        outline.rowHeight = AppSettings.sidebarRowHeight(fontSize: GhosttyApp.shared.sidebarFontSize)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: Self.narrowSidebar, height: 400))
        scroll.documentView = outline
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.narrowSidebar, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        // over-releases a window the registry may still hold, crashing the host at autorelease-pool pop
        window.isReleasedWhenClosed = false
        window.contentView = scroll

        coordinator.outlineView = outline
        coordinator.renameController.outlineView = outline
        coordinator.seedExpansionFromModel()
        coordinator.reconcile()
        setSidebarWidth(Self.narrowSidebar)
    }

    /// Both widths these tests use must stay inside the divider's own 160...560 range, or a truncation
    /// threshold that no drag can actually clear would still pass here.
    private static let narrowSidebar: CGFloat = 240

    /// Drives the width the way a divider drag does: the column tracks the outline, and the row views retile
    /// off that. Without it the column keeps its default width and every row measures the same regardless of
    /// the window, which makes a truncation assertion pass for the wrong reason.
    private func setSidebarWidth(_ width: CGFloat) {
        window.setContentSize(NSSize(width: width, height: 400))
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        outline.frame = NSRect(x: 0, y: 0, width: width, height: outline.frame.height)
        outline.sizeLastColumnToFit()
        outline.layoutSubtreeIfNeeded()
    }

    private func renderedNameField(forSession id: UUID) throws -> NSTextField {
        let cell = try renderedCell(forSession: id)
        cell.layoutSubtreeIfNeeded()
        return try XCTUnwrap(cell.textField)
    }

    private func renderedCell(forSession id: UUID) throws -> SidebarCellView {
        outline.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap((0..<outline.numberOfRows).first { index in
            guard let node = outline.item(atRow: index) as? SidebarNode else { return false }
            return node.kind == .session && node.id == id
        }, "the session row should be visible in the outline")
        return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCellView)
    }

    private func renderedIcon(forRow id: UUID) throws -> NSImage? {
        try renderedRowCell(forRow: id).imageView?.image
    }

    private func glyphAlpha(forRow id: UUID) throws -> CGFloat {
        try XCTUnwrap(renderedRowCell(forRow: id).imageView?.contentTintColor).alphaComponent
    }

    private func renderedRowCell(forRow id: UUID) throws -> SidebarCellView {
        outline.layoutSubtreeIfNeeded()
        let row = try XCTUnwrap((0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarNode)?.id == id },
                                "the row should be visible in the outline")
        return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCellView)
    }
}
