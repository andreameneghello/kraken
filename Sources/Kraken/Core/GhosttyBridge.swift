import AppKit
import GhosttyKit
import Observation

/// Bridge between Kraken and the libghostty C API.
///
/// Manages the single `ghostty_app_t` instance and provides helpers
/// for creating terminal surfaces. This class is a singleton-like
/// observable owned by the app root.
@Observable
final class GhosttyBridge {
    /// The underlying Ghostty app handle. Valid after initialization.
    private(set) var app: ghostty_app_t?

    /// The config handle used to create the app.
    private var config: ghostty_config_t?

    @MainActor
    init() {
        // Initialize Ghostty global state once per process.
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            fatalError("ghostty_init failed")
        }

        // Load default configuration.
        let cfg = ghostty_config_new()
        ghostty_config_load_default_files(cfg)
        ghostty_config_finalize(cfg)
        self.config = cfg

        // Runtime callbacks bridge Ghostty core events into Swift.
        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyBridge.wakeup(userdata) },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { userdata, loc, state in
                GhosttyBridge.readClipboard(userdata: userdata, location: loc, state: state)
            },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { userdata, loc, content, len, confirm in
                GhosttyBridge.writeClipboard(userdata: userdata, location: loc, content: content, len: len, confirm: confirm)
            },
            close_surface_cb: { _, _ in }
        )

        guard let app = ghostty_app_new(&runtime, cfg) else {
            fatalError("ghostty_app_new failed")
        }
        self.app = app
    }

    deinit {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    @MainActor
    /// Called by Ghostty when it needs the app to process pending events.
    func appTick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// Create a `ghostty_surface_t` attached to `view`, optionally overriding
    /// the startup command (e.g. a tmux attach command).
    func createSurface(for view: TerminalSurfaceView, command: String? = nil) -> ghostty_surface_t? {
        guard let app else { return nil }
        var cfg = ghostty_surface_config_new()
        cfg.userdata = Unmanaged.passUnretained(view).toOpaque()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(view).toOpaque()
            )
        )
        cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)

        return NSHomeDirectory().withCString { cwdPtr in
            cfg.working_directory = cwdPtr
            if let command {
                return command.withCString { cmdPtr in
                    cfg.command = cmdPtr
                    return ghostty_surface_new(app, &cfg)
                }
            }
            return ghostty_surface_new(app, &cfg)
        }
    }

    // MARK: - C Callbacks

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        // Bridge the pointer through Int to avoid Swift 6.2 Sendable warnings.
        // The pointer value is immutable here; it is only used to look up the bridge.
        let bits = Int(bitPattern: userdata)
        Task { @MainActor in
            let ptr = UnsafeMutableRawPointer(bitPattern: bits)!
            let bridge = Unmanaged<GhosttyBridge>.fromOpaque(ptr).takeUnretainedValue()
            bridge.appTick()
        }
    }

    /// Clipboard read callback — Ghostty wants to paste.
    /// `userdata` is the TerminalSurfaceView (surface userdata).
    @MainActor
    private static func readClipboard(
        userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        let view = Unmanaged<TerminalSurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
        guard let surface = view.ghosttySurface else { return false }

        let pb = NSPasteboard.general
        guard let str = pb.string(forType: .string) else { return false }

        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    /// Clipboard write callback — Ghostty wants to copy.
    /// `userdata` is the TerminalSurfaceView (surface userdata).
    @MainActor
    private static func writeClipboard(
        userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }
        let pb = NSPasteboard.general
        pb.clearContents()

        for i in 0..<len {
            let item = content[i]
            guard let mime = item.mime else { continue }
            guard let data = item.data else { continue }
            if String(cString: mime) == "text/plain" {
                pb.setString(String(cString: data), forType: .string)
            }
        }
    }
}
