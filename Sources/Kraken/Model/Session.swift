import Foundation

/// A single session exposed to the UI.
/// The session name is the canonical identifier.
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expanded: String
        if path.hasPrefix("~") {
            expanded = home.path + path.dropFirst()
        } else {
            expanded = path
        }
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        let homeStandardized = home.standardizedFileURL.path
        if standardized == homeStandardized { return "~" }
        return URL(fileURLWithPath: standardized).lastPathComponent
    }

    /// Human-readable relative time since creation.
    var timeAgo: String {
        guard let date = creationDate else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}
