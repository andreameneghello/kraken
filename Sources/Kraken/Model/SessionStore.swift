import Foundation
import SwiftUI

/// Observable store that mirrors the tmux session list.
@Observable
@MainActor
final class SessionStore {
    var sessions: [Session] = []
    var expandedProjects: Set<String> = []
    var selection: Set<String> = []
    var detailSessionID: String? {
        selection.first { id in sessions.contains(where: { $0.id == id }) }
    }

    private let tmux = TmuxController()
    private var isPolling = false

    init() {
        startPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        Task {
            while isPolling {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Actions

    func refresh() {
        let infos = tmux.listSessionInfos()
        let oldNames = Set(sessions.map(\.id))
        let oldGroups = Set(groupedSessions.map(\.project))
        let newSessions = infos.map { Session(name: $0.name, path: $0.path, creationDate: $0.creationDate) }
        let newNames = Set(newSessions.map(\.id))
        let gone = oldNames.subtracting(newNames)

        sessions = newSessions

        let newGroups = Set(groupedSessions.map(\.project))
        // Auto-expand only newly-seen groups
        for group in newGroups.subtracting(oldGroups) {
            expandedProjects.insert(group)
        }

        // Remove dead sessions from selection
        if !gone.isEmpty {
            selection.subtract(gone)
        }
    }

    /// Sessions grouped by project, with collision disambiguation.
    /// If two sessions share the same project name but have different paths,
    /// the parent directory is appended: "kraken (repos)" vs "kraken (other)".
    var groupedSessions: [(project: String, sessions: [Session])] {
        let byProject = Dictionary(grouping: sessions) { $0.project }
        var result: [(project: String, sessions: [Session])] = []

        for project in byProject.keys.sorted() {
            let sessionsInProject = byProject[project]!
            let byPath = Dictionary(grouping: sessionsInProject) { $0.path ?? "" }

            if byPath.count == 1 {
                // No collision — simple name
                result.append((project, sessionsInProject.sorted { $0.name < $1.name }))
            } else {
                // Collision — disambiguate with parent directory
                for (path, pathSessions) in byPath.sorted(by: { $0.key < $1.key }) {
                    let displayName = disambiguatedProjectName(base: project, path: path)
                    result.append((displayName, pathSessions.sorted { $0.name < $1.name }))
                }
            }
        }

        return result.sorted { $0.project < $1.project }
    }

    /// Return a map from disambiguated project name → directory path for creation.
    var projectDirectories: [String: String] {
        var map: [String: String] = [:]
        for s in sessions {
            let display = disambiguatedProjectName(base: s.project, path: s.path ?? "")
            if map[display] == nil, let path = s.path {
                map[display] = path
            }
        }
        return map
    }

    func toggleProject(_ project: String) {
        if expandedProjects.contains(project) {
            expandedProjects.remove(project)
        } else {
            expandedProjects.insert(project)
        }
    }

    func createSession(name: String, inProject project: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let directory = project.flatMap { projectDirectories[$0] }
        let success = tmux.createSession(name: trimmed, directory: directory)
        guard success else { return }
        refresh()
        selection = [trimmed]
    }

    func killSelected() {
        for id in selection {
            tmux.killSession(name: id)
        }
        refresh()
    }

    func killSession(id: String) {
        tmux.killSession(name: id)
        refresh()
    }

    func renameSession(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != id else { return }
        tmux.renameSession(oldName: id, newName: trimmed)
        refresh()
        if selection.contains(id) {
            selection.remove(id)
            selection.insert(trimmed)
        }
    }

    func selectAll() {
        selection = Set(sessions.map(\.id))
    }

    func deselectAll() {
        selection = []
    }

    // MARK: - Private

    /// Disambiguate a project name by appending the parent directory when needed.
    private func disambiguatedProjectName(base: String, path: String) -> String {
        if path.isEmpty || path == NSHomeDirectory() {
            return base
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        if parent.isEmpty || parent == "/" {
            return base
        }
        return "\(base) (\(parent))"
    }
}
