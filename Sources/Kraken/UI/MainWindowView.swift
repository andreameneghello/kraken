import SwiftUI

struct MainWindowView: View {
    @Environment(GhosttyBridge.self) private var bridge
    @State private var store = SessionStore()
    @State private var isCreating = false
    @State private var newName = ""
    @State private var createInProject: String? = nil
    @State private var searchText = ""

    private var detailSessionID: String? { store.detailSessionID }
    private var selectionCount: Int { store.selection.count }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                groupedSessions: store.groupedSessions,
                selection: $store.selection,
                expandedProjects: $store.expandedProjects,
                searchText: $searchText,
                onKill: { store.killSession(id: $0) },
                onRename: { store.renameSession(id: $0, to: $1) },
                onCreateInProject: { project in
                    createInProject = project
                    newName = ""
                    isCreating = true
                },
                onCreate: {
                    createInProject = nil
                    newName = ""
                    isCreating = true
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detailContent
                .navigationSplitViewColumnWidth(min: 500, ideal: 800)
        }
        .onAppear {
            store.refresh()
        }
        .alert("New Session", isPresented: $isCreating) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            Button("Create") {
                store.createSession(name: newName, inProject: createInProject)
                createInProject = nil
            }
            Button("Cancel", role: .cancel) {
                createInProject = nil
            }
        } message: {
            if let project = createInProject {
                Text("Create a new session in project '\(project)'.")
            } else {
                Text("Enter a name for the new tmux session.")
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let sessionID = detailSessionID {
            TerminalPaneView(sessionID: sessionID, bridge: bridge)
                .navigationTitle(sessionID)
        } else if selectionCount > 1 {
            multiSelectionState
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Select a session", systemImage: "terminal")
        } description: {
            Text("Choose a tmux session from the sidebar, or create a new one with ⌘N.")
        }
    }

    private var multiSelectionState: some View {
        ContentUnavailableView {
            Label("\(selectionCount) sessions selected", systemImage: "terminal")
        } actions: {
            Button("Kill Selected") {
                store.killSelected()
            }
        }
    }
}
