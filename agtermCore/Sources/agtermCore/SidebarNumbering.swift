import Foundation

/// A sidebar row's leading glyph shows its 1-based VISIBLE position among the rows the outline renders:
/// workspaces over `AppStore.workspaceProjection`, sessions from 1 among that row's sessions, or down the whole list
/// under the flat flagged layout, which has no workspace rows.
public enum SidebarNumbering {
    /// The digit keys reach ten rows: the tenth draws `0`, every later row the stub.
    public static func symbolName(forPosition position: Int?) -> String {
        guard let position, (1 ... 10).contains(position) else { return "circle.dashed" }
        return "\(position % 10).circle"
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
