import SwiftUI

struct SidebarView: View {
    let groupedSessions: [(project: String, sessions: [Session])]
    @Binding var selection: Set<String>
    @Binding var expandedProjects: Set<String>
    @Binding var searchText: String
    let onKill: (String) -> Void
    let onRename: (String, String) -> Void
    let onCreateInProject: ((String) -> Void)?
    let onCreate: (() -> Void)?

    @State private var renameSessionID: String?
    @State private var renameText = ""
    @State private var isRenaming = false

    private enum SidebarItemKind {
        case project(name: String, expanded: Bool)
        case session(Session)
    }

    private struct SidebarItem: Identifiable {
        let id: String
        let kind: SidebarItemKind
    }

    private var filteredGroups: [(project: String, sessions: [Session])] {
        if searchText.isEmpty { return groupedSessions }
        return groupedSessions.compactMap { group in
            let matching = group.sessions.filter {
                $0.name.localizedStandardContains(searchText)
            }
            guard !matching.isEmpty else { return nil }
            return (group.project, matching)
        }
    }

    private var flattenedItems: [SidebarItem] {
        let groups = filteredGroups
        var items: [SidebarItem] = []
        for group in groups {
            let expanded = expandedProjects.contains(group.project)
            items.append(SidebarItem(
                id: "project:\(group.project)",
                kind: .project(name: group.project, expanded: expanded)
            ))
            if expanded {
                for session in group.sessions {
                    items.append(SidebarItem(
                        id: session.id,
                        kind: .session(session)
                    ))
                }
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar header with search and action buttons
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Filter", text: $searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.roundedBorder)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Spacer()

                Button {
                    onCreate?()
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("New Session")

                if !selection.isEmpty {
                    Button {
                        for id in selection {
                            onKill(id)
                        }
                        selection = []
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Kill Selected")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(flattenedItems, selection: $selection) { item in
                switch item.kind {
                case .project(let name, let expanded):
                    projectRow(name: name, expanded: expanded)
                        .selectionDisabled()
                case .session(let session):
                    row(for: session)
                        .tag(session.id)
                }
            }
            .listStyle(.sidebar)
            .scrollIndicators(.hidden)
            .overlay {
                if flattenedItems.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No sessions match '\(searchText)'.")
                    }
                }
            }
        }
        .alert("Rename Session", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .autocorrectionDisabled()
            Button("Rename") {
                guard let id = renameSessionID else { return }
                onRename(id, renameText)
                renameSessionID = nil
            }
            Button("Cancel", role: .cancel) { renameSessionID = nil }
        }
    }

    private func projectRow(name: String, expanded: Bool) -> some View {
        Button {
            if expandedProjects.contains(name) {
                expandedProjects.remove(name)
            } else {
                expandedProjects.insert(name)
            }
        } label: {
            HStack {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                Text(name)
                    .bold()
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("New Session") {
                onCreateInProject?(name)
            }
        }
    }

    private func row(for session: Session) -> some View {
        HStack {
            Image(systemName: "terminal")
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                if !session.timeAgo.isEmpty {
                    Text(session.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .tag(session.id)
        .contextMenu {
            Button("Rename") {
                renameSessionID = session.id
                renameText = session.name
                isRenaming = true
            }
            Button("Kill", role: .destructive) {
                onKill(session.id)
            }
        }
    }
}
