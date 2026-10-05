import AppKit
import agtermCore

extension WorkspaceSidebar.Coordinator {
    /// The flagged view's layout while the sidebar shows it, nil in the ordinary tree. A change to THIS value,
    /// not to the global setting, is what re-shapes the outline: the setting is dormant under the ordinary tree.
    var flaggedLayout: FlaggedViewLayout? {
        store.sidebarMode == .flagged ? GhosttyApp.shared.flaggedViewLayout : nil
    }

    var rendersWorkspaceRows: Bool {
        store.rendersWorkspaceRows(flaggedLayout: GhosttyApp.shared.flaggedViewLayout)
    }

    /// The unseen count a workspace row shows: its RENDERED children's. `Workspace.unseenCount` sums every
    /// session, so a flagged-tree header would otherwise report notifications from rows the view leaves out.
    func displayedUnseen(for workspace: Workspace) -> Int {
        guard flaggedLayout == .tree else { return workspace.unseenCount }
        return workspace.sessions.reduce(0) { $1.flagged ? $0 + $1.unseenCount : $0 }
    }
}
