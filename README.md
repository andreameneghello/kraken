# Kraken

A native macOS terminal session orchestrator for AI CLI tools.

## What is Kraken?

Kraken is a native macOS app that manages persistent terminal sessions for AI-powered CLI tools like Claude Code, Kiro, and Pi. Think of it as an **AI tool launcher with session history** — not an SSH manager, not an IDE, and not a chat UI.

The problem: AI CLI tools are powerful but their sessions vanish when you close the terminal. There is no persistent sidebar of past sessions. Kraken fills this gap with a native macOS interface that runs each session inside a real embedded terminal, tracks metadata (name, AI tool, working directory), and keeps everything alive across app restarts via an invisible tmux backend.

## What it is not

- Not an SSH client (use Termius for that).
- Not a code editor (use Zed or Cursor for that).
- Not a chat interface (it is a real terminal, not a message thread).

## Features

- **Native macOS sidebar** listing all active and past terminal sessions, grouped by working directory.
- **Real embedded terminals** powered by [libghostty](https://github.com/ghostty-org/ghostty) — the same terminal engine used by Ghostty.
- **Persistent sessions** via tmux running silently in the background. Quit Kraken, relaunch it, your sessions are still there.
- **Session metadata** — custom names, working directories, timestamps, and search.
- **macOS-native feel** — built with SwiftUI, standard keyboard shortcuts, and Metal-accelerated rendering.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Swift + SwiftUI (`NavigationSplitView`) |
| Terminal emulation | libghostty (C API, Metal renderer) |
| Session persistence | tmux (invisible background daemon) |
| Session metadata | SQLite |
| Build | Xcode + pre-built `GhosttyKit.xcframework` |

## Project Structure

```
Kraken/
├── App/              — Entry point, app lifecycle, delegates
├── Core/             — libghostty C bridge and tmux controller
├── UI/               — SwiftUI views (sidebar, terminal pane, toolbar)
├── Model/            — Domain models (Session) and observable store
└── Helpers/          — Extensions and utilities
```

## Getting Started

### Prerequisites

- **macOS 14+**
- **Xcode 16+** (required to build `GhosttyKit.xcframework`)
- **Zig 0.15.x** (`brew install zig@0.15`)

### 1. Build the GhosttyKit xcframework

Clone the Ghostty repo and build the framework:

```bash
cd /path/to/ghostty
zig build -Demit-xcframework
```

Copy the result into this project:

```bash
cp -R /path/to/ghostty/zig-out/lib/GhosttyKit.xcframework \
      /path/to/kraken/Frameworks/
```

### 2. Build and run

Open `Package.swift` in Xcode and press **Cmd+R**, or use the Makefile:

```bash
make run
```

## Debugging

### The terminal surface is blank (no rendering)

- Check that `GhosttyKit.xcframework` is embedded (not just linked).
- Ensure `TerminalSurfaceView` sets the `nsview` field in `ghostty_surface_config_s` to `self`.
- Verify Metal is available on your Mac (virtually all Apple Silicon and recent Intel Macs).

### Keyboard input does not reach the terminal

- Confirm `TerminalSurfaceView.acceptsFirstResponder` returns `true`.
- Check that `ghostty_surface_set_focus(surface, true)` is called when the view becomes first responder.
- Review the focus chain in Xcode's **View Debugger** (Debug → View Debugging → Capture View Hierarchy).

### Sessions do not persist across app restarts

- Verify tmux is installed: `which tmux` should return a path.
- Check that tmux commands use the `-L kraken` socket flag (isolated from user tmux sessions).
- Inspect the SQLite database at `~/Library/Application Support/Kraken/sessions.db`.

### Crash on surface creation

- Check the Xcode console for C API errors. libghostty may fail if the config is invalid or the Metal layer cannot be initialized.
- Ensure `ghostty_app_new()` succeeded (it returns `nil` on failure).

## Local Testing

### Reset application state

To wipe all sessions and the database during development:

```bash
rm -rf ~/Library/Application\ Support/Kraken/
```

### Inspect tmux sessions

```bash
tmux -L kraken list-sessions
tmux -L kraken attach -t <session-name>
```

### Test the C bridge in isolation

The Ghostty repo contains a minimal Swift example:

```bash
cd /path/to/ghostty/example/swift-vt-xcframework
swift build
swift run
```

This proves the xcframework links and runs independently of Kraken's UI.

## License

[MIT](LICENSE)
