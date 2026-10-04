import Foundation

/// A sidebar row's leading glyph shows its 1-based VISIBLE position: workspaces count over
/// `visibleWorkspaces`, sessions from 1 inside their workspace. Flagged mode has no positions (nil), drawn
/// as the stub.
public enum SidebarNumbering {
    /// The digit keys reach ten rows: the tenth draws `0`, every later row the stub.
    public static func symbolName(forPosition position: Int?) -> String {
        guard let position, (1 ... 10).contains(position) else { return "circle.dashed" }
        return "\(position % 10).circle"
    }

    @MainActor
    public static func position(ofWorkspace id: UUID, in store: AppStore) -> Int? {
        guard store.sidebarMode == .tree,
              let index = store.visibleWorkspaces.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    @MainActor
    public static func position(ofSession id: UUID, in store: AppStore) -> Int? {
        guard let workspace = store.workspace(forSession: id), position(ofWorkspace: workspace.id, in: store) != nil,
              let index = workspace.sessions.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }
}
