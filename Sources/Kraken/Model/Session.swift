import Foundation

/// A single tmux session exposed to the UI.
/// The tmux session name is the canonical identifier.
struct Session: Identifiable, Hashable, Sendable {
    let id: String
    var name: String { id }
    let project: String
    let path: String?
    let creationDate: Date?

    init(name: String, path: String? = nil, creationDate: Date? = nil) {
        self.id = name
        self.path = path
        self.creationDate = creationDate
        self.project = Session.projectName(from: path)
    }

    /// Derive a project name from a filesystem path.
    /// - Empty / nil path → "~"
    /// - Home directory → "~"
    /// - Anything else → last path component
    static func projectName(from path: String?) -> String {
        guard let path, !path.isEmpty else { return "~" }
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        let home = (NSHomeDirectory() as NSString).standardizingPath
        if standardized == home { return "~" }
        return URL(fileURLWithPath: standardized).lastPathComponent
    }

    /// Human-readable relative time since creation.
    var timeAgo: String {
        guard let date = creationDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
