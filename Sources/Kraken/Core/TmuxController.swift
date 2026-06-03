import Foundation

struct SessionInfo: Sendable {
    let name: String
    let path: String?
    let creationDate: Date?
}

/// Shells out to tmux using a dedicated socket (`-L kraken`) so we never
/// interfere with the user’s existing tmux sessions.
@MainActor
final class TmuxController {
    static let socketName = "kraken"

    /// Path to the Kraken-controlled tmux config file.
    /// The config disables tmux copy mode on scroll so Ghostty handles
    /// scrolling natively with pixel-smooth scrollback.
    private static var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Kraken/tmux.conf")
            .path
    }

    /// List all tmux session names. Returns empty array if tmux server is not running.
    func listSessions() -> [String] {
        listSessionInfos().map(\.name)
    }

    /// List all tmux sessions with their current working directory paths and creation times.
    func listSessionInfos() -> [SessionInfo] {
        let result = runTmux(
            args: ["list-sessions", "-F", "#{session_name}\t#{pane_current_path}\t#{session_created}"],
            includeStderr: false
        )
        guard result.exitCode == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let path = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
                let createdString = parts.count > 2 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : nil
                guard !name.isEmpty else { return nil }
                let cleanPath = path?.isEmpty == false ? path : nil
                let creationDate = createdString.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
                return SessionInfo(name: name, path: cleanPath, creationDate: creationDate)
            }
    }

    /// Create a new detached tmux session.
    /// Uses `directory` if provided, otherwise falls back to the user's home directory.
    func createSession(name: String, directory: String? = nil) -> Bool {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let result = runTmux(args: ["new-session", "-s", name, "-d", "-c", dir])
        return result.exitCode == 0 || listSessions().contains(name)
    }

    /// Kill a tmux session.
    func killSession(name: String) {
        _ = runTmux(args: ["kill-session", "-t", name])
    }

    /// Rename a tmux session.
    func renameSession(oldName: String, newName: String) {
        _ = runTmux(args: ["rename-session", "-t", oldName, newName])
    }

    /// Build the shell command that attaches to a named tmux session.
    static func attachCommand(for sessionName: String) -> String {
        "\(tmuxPath) -L \(socketName) -f \"\(configPath)\" attach -t \(sessionName)"
    }

    // MARK: - Private

    private static let tmuxPath: String = {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "/bin/tmux",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "tmux"
    }()

    private struct RunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Run tmux and capture stdout/stderr separately.
    /// Always uses the Kraken-controlled config file (`-f`) and dedicated socket (`-L`).
    private func runTmux(args: [String], includeStderr: Bool = true) -> RunResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.tmuxPath)
        task.arguments = ["-L", TmuxController.socketName, "-f", Self.configPath] + args

        // Suppress Powerlevel10k and nvm console noise in new shells
        var env = ProcessInfo.processInfo.environment
        env["POWERLEVEL9K_INSTANT_PROMPT"] = "quiet"
        env["npm_config_prefix"] = ""
        task.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return RunResult(stdout: "", stderr: "", exitCode: -1)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let exitCode = task.terminationStatus

        if includeStderr && !stderr.isEmpty {
            return RunResult(stdout: stdout + "\n" + stderr, stderr: stderr, exitCode: exitCode)
        }
        return RunResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}
