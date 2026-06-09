import Foundation
import Darwin

/// Shells out to zmx using a dedicated socket directory so we never
/// interfere with the user's existing zmx sessions.
///
/// Zmx is a session persistence layer with libghostty-vt state restoration.
/// Unlike abduco (unmaintained since 2016), zmx replays full terminal state
/// on reattach — no blank screen. Like abduco, it does not parse terminal
/// control sequences or intercept scroll events, so Ghostty retains 100%
/// native control of scrollback, selection, and rendering.
@MainActor
final class ZmxController {
    /// Short socket directory to avoid macOS 104-char Unix socket limit.
    /// zmx stores one socket file per session here, plus ./logs/zmx.log.
    static let socketDir = "/tmp/krkn"

    /// Prefix for all session names owned by this app.
    /// Avoids collisions with any zmx sessions the user creates outside Kraken.
    static let sessionPrefix = "kraken."

    /// Apply the session prefix to a user-provided name.
    static func prefixed(_ name: String) -> String {
        name.hasPrefix(sessionPrefix) ? name : "\(sessionPrefix)\(name)"
    }

    /// Strip the app prefix from a zmx session name for display.
    static func unprefixed(_ name: String) -> String {
        name.hasPrefix(sessionPrefix) ? String(name.dropFirst(sessionPrefix.count)) : name
    }

    /// Path to the zmx binary.
    static let zmxPath: String = {
        let candidates = [
            "/opt/homebrew/bin/zmx",
            "/usr/local/bin/zmx",
            "/usr/bin/zmx",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/opt/homebrew/bin/zmx"
    }()

    init() {
        // Ensure socket directory exists.
        try? FileManager.default.createDirectory(
            atPath: Self.socketDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Session Lifecycle

    /// List all zmx session names (with app prefix stripped for display).
    func listSessions() -> [String] {
        let result = runZmx(args: ["list", "--short"])
        guard result.exitCode == 0, !result.stdout.isEmpty else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix(Self.sessionPrefix) }
            .map { Self.unprefixed($0) }
    }

    /// List sessions with full detail (with app prefix stripped for display).
    /// zmx list output format (tab-separated key=value):
    /// name=X \t pid=X \t clients=X \t created=X \t start_dir=X
    struct ZmxSession {
        let name: String
        let pid: String
        let clients: Int
        let directory: String
    }

    func listSessionsDetailed() -> [ZmxSession] {
        let result = runZmx(args: ["list"])
        guard result.exitCode == 0, !result.stdout.isEmpty else { return [] }

        return result.stdout.split(separator: "\n").compactMap { line in
            // Parse key=value fields by key name, not position.
            // zmx output has 5+ tab-separated fields; field order may change.
            // Lines have leading whitespace that must be trimmed.
            let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            var dict: [String: String] = [:]
            for field in fields {
                let kv = field.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { dict[kv[0]] = kv[1] }
            }

            guard let rawName = dict["name"],
                  rawName.hasPrefix(Self.sessionPrefix) else { return nil }

            let pidString = dict["pid"] ?? "?"
            let pid = Int32(pidString) ?? 0
            let liveDir = pid > 0 ? Self.cwdOfProcess(pid: pid) : nil

            return ZmxSession(
                name:      Self.unprefixed(rawName),
                pid:       pidString,
                clients:   Int(dict["clients"] ?? "0") ?? 0,
                directory: liveDir ?? (dict["start_dir"] ?? dict["started_in"] ?? "")
            )
        }
    }

    /// Create a new zmx session by spawning a short-lived attach, then
    /// killing the client. The session persists without clients attached.
    func createSession(name: String, directory: String? = nil) -> Bool {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let prefixed = Self.prefixed(name)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.zmxPath)
        proc.arguments = ["attach", prefixed]
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)

        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = Self.socketDir
        proc.environment = env

        // Close stdin so zmx doesn't block waiting for input.
        let nullIn = Pipe()
        proc.standardInput = nullIn

        let nullOut = Pipe()
        proc.standardOutput = nullOut
        proc.standardError = nullOut

        do {
            try proc.run()
        } catch {
            return false
        }

        // Give zmx time to fork the shell and create the session.
        Thread.sleep(forTimeInterval: 0.5)

        // Kill the zmx client process — the session survives.
        proc.terminate()
        proc.waitUntilExit()

        return listSessions().contains(name)
    }

    /// Kill a zmx session.
    func killSession(name: String) {
        _ = runZmx(args: ["kill", Self.prefixed(name)])
    }

    /// Force-kill a zmx session even if clients are attached.
    func forceKillSession(_ name: String) {
        _ = runZmx(args: ["kill", Self.prefixed(name), "--force"])
    }

    /// Build the shell command string that attaches to a named zmx session.
    ///
    /// Uses /usr/bin/env to set ZMX_DIR because shell VAR=val assignment
    /// syntax does not survive Ghostty's `exec -l` argument tokenization.
    /// This returns a single String (not [String]) because the libghostty C API
    /// takes a single shell command via `cfg.command`.
    static func attachCommand(for sessionName: String) -> String {
        let prefixed = Self.prefixed(sessionName)
        return "/usr/bin/env ZMX_DIR=\(socketDir) \(zmxPath) attach \(prefixed)"
    }

    // MARK: - Sending Commands to Sessions

    /// Send a shell command to a running zmx session. Returns stdout.
    /// NOT safe for interactive programs (pagers, editors, prompts).
    @discardableResult
    func runCommand(_ command: String, in session: String) -> String {
        let prefixed = Self.prefixed(session)
        let parts = command.split(separator: " ").map(String.init)
        let result = runZmx(args: ["run", prefixed] + parts)
        return result.stdout
    }

    /// Send raw bytes to a session's PTY. Fire-and-forget.
    /// No carriage return is appended — add `\r` yourself to execute.
    func sendRaw(_ text: String, to session: String) {
        _ = runZmx(args: ["send", Self.prefixed(session), text])
    }

    /// Send text followed by Enter to a zmx session.
    func sendCommand(_ text: String, to session: String) {
        _ = runZmx(args: ["send", Self.prefixed(session), text + "\r"])
    }

    /// Run a detached command in a session. Returns immediately.
    func runDetached(_ command: String, in session: String) {
        let prefixed = Self.prefixed(session)
        let parts = command.split(separator: " ").map(String.init)
        _ = runZmx(args: ["run", prefixed, "-d"] + parts)
    }

    /// Block until all detached tasks in a session complete.
    func waitForSession(_ name: String) {
        _ = runZmx(args: ["wait", Self.prefixed(name)])
    }

    /// Read the last N lines of session scrollback history.
    func getHistory(_ name: String, lines: Int = 100) -> String {
        let result = runZmx(args: ["history", Self.prefixed(name)])
        let allLines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        return allLines.suffix(lines).joined(separator: "\n")
    }

    /// Follow session output as a stream. Returns a Process you can terminate.
    func tailSession(_ name: String, handler: @escaping (String) -> Void) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.zmxPath)
        proc.arguments = ["tail", Self.prefixed(name)]

        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = Self.socketDir
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                DispatchQueue.main.async { handler(text) }
            }
        }

        try? proc.run()
        return proc
    }

    // MARK: - Version & Known Issues

    /// Returns the zmx version string (e.g. "0.6.0").
    func version() -> String {
        let result = runZmx(args: ["version"])
        let firstLine = result.stdout.split(separator: "\n").first.map(String.init) ?? result.stdout
        return firstLine.replacingOccurrences(of: "zmx\t\t", with: "")
    }

    /// Verify zmx version matches the expected bundled version.
    /// Upgrading zmx can kill all sessions due to IPC changes.
    func verifyVersion(expected: String = "0.6.0") -> Bool {
        version().hasPrefix(expected)
    }

    /// Send Ctrl+C to a hung zmx run command.
    func cancelHungCommand(in session: String) {
        let ctrlC = "\u{03}"  // ASCII ETX
        sendRaw(ctrlC, to: session)
    }

    // MARK: - Process CWD (live directory tracking)

    /// Read the current working directory of a process by PID.
    /// Uses `proc_pidinfo` (no command injection, no terminal disruption).
    static func cwdOfProcess(pid: Int32) -> String? {
        var vpi = proc_vnodepathinfo()
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0,
                               &vpi, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard ret > 0 else { return nil }
        return withUnsafePointer(to: vpi.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    // MARK: - Private

    private struct RunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Run zmx and capture stdout/stderr separately.
    private func runZmx(args: [String]) -> RunResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.zmxPath)
        task.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["ZMX_DIR"] = Self.socketDir
        task.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return RunResult(stdout: "", stderr: "\(error)", exitCode: -1)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                         stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                         exitCode: task.terminationStatus)
    }
}
