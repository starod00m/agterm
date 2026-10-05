import Foundation

/// A sidebar row's leading glyph shows its 1-based VISIBLE position among the rows the outline renders:
/// workspaces over `AppStore.workspaceProjection`, sessions from 1 among that row's sessions, or down the whole list
/// under the flat flagged layout, which has no workspace rows.
public enum SidebarNumbering {
    /// The digit keys reach ten rows: every later row, or one with no position, draws the keyless stub.
    public static func isStub(_ position: Int?) -> Bool {
        guard let position else { return true }
        return !(1 ... 10).contains(position)
    }

    /// The tenth row draws `0`. A flag fills the circle; the stub has no filled form, so it hides the flag.
    public static func symbolName(forPosition position: Int?, flagged: Bool = false) -> String {
        guard let position, !isStub(position) else { return "circle.dashed" }
        return "\(position % 10).circle" + (flagged ? ".fill" : "")
    }

    /// Flagged modes show only flagged rows, so a fill there would mark every row: only the ordinary tree shows it.
    /// Takes the resolved session: the reconcile loop already holds it, and a lookup per row would make it quadratic.
    @MainActor
    public static func showsFlag(of session: Session, in store: AppStore) -> Bool {
        store.sidebarMode == .tree && session.flagged
    }

    /// Membership, not the filter: a marked workspace and its sessions stay bright with the filter off.
    /// Flagged modes ignore focus.
    @MainActor
    public static func isFocusMember(workspace id: UUID, in store: AppStore) -> Bool {
        store.sidebarMode == .tree && store.focusedWorkspaceIDs.contains(id)
    }

    @MainActor
    public static func isFocusMember(session id: UUID, in store: AppStore) -> Bool {
        guard let workspace = store.workspace(forSession: id) else { return false }
        return isFocusMember(workspace: workspace.id, in: store)
    }

    @MainActor
    public static func position(ofWorkspace id: UUID, in store: AppStore, flaggedLayout: FlaggedViewLayout) -> Int? {
        guard store.rendersWorkspaceRows(flaggedLayout: flaggedLayout),
              let index = store.workspaceProjection.firstIndex(where: { $0.workspace.id == id }) else { return nil }
        return index + 1
    }

    @MainActor
    public static func position(ofSession id: UUID, in store: AppStore, flaggedLayout: FlaggedViewLayout) -> Int? {
        let rows: [Session]? = store.rendersWorkspaceRows(flaggedLayout: flaggedLayout)
            ? store.workspaceProjection.first { $0.sessions.contains { $0.id == id } }?.sessions
            : store.flaggedSessions
        guard let index = rows?.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }
}
