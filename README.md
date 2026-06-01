# Kraken

A native macOS terminal session orchestrator for AI CLI tools.

## What is Kraken?

Kraken is a native macOS app that manages persistent terminal sessions for AI-powered CLI tools like Claude Code, Kiro, and Pi. Think of it as an **AI tool launcher with session history** — not an SSH manager, not an IDE, and not a chat UI.

The problem: AI CLI tools are powerful but their sessions vanish when you close the terminal. There is no persistent sidebar of past sessions. Kraken fills this gap with a native macOS interface that runs each session inside a real embedded terminal, tracks metadata (name, AI tool, working directory), and keeps everything alive across app restarts via an invisible tmux backend.

## What it is not

- Not an SSH client (use Termius for that).
- Not a code editor (use Zed or Cursor for that).
- Not a chat interface (it is a real terminal, not a message thread).

## Features (planned)

- **Native macOS sidebar** listing all active and past terminal sessions.
- **Real embedded terminals** powered by [libghostty](https://github.com/ghostty-org/ghostty) — the same terminal engine used by Ghostty.
- **Persistent sessions** via tmux running silently in the background. Quit Kraken, relaunch it, your sessions are still there.
- **AI tool association** — tag sessions with the tool they run (Claude Code, Kiro, Pi, or custom).
- **Session metadata** — custom names, working directories, timestamps, and search.
- **macOS-native feel** — built with SwiftUI, standard keyboard shortcuts, proper focus management, and Metal-accelerated rendering.

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
├── Core/             — libghostty C bridge (app init, surface lifecycle, config)
├── UI/               — SwiftUI views (sidebar, terminal pane, toolbar)
├── Model/            — Domain models (Session, AICommand, etc.)
├── Persistence/      — SQLite setup and session repository
├── Tmux/             — tmux daemon controller and command builders
└── Helpers/          — Extensions, constants
```

See [`plan.md`](plan.md) for the full phased implementation plan.

## Prerequisites

- **macOS 14+**
- **Xcode 16+**
- **Zig** (to build the `GhosttyKit.xcframework`):
  ```bash
  brew install zig
  ```

## Getting Started

### 1. Clone this repo and the Ghostty reference repo

```bash
git clone <this-repo> ~/repos/kraken
# Ghostty source should already be at:
# ~/repos/cloned-repos/ghostty
```

### 2. Build the GhosttyKit xcframework

```bash
cd ~/repos/cloned-repos/ghostty
zig build -Demit-xcframework
```

This produces:
```
ghostty/zig-out/lib/GhosttyKit.xcframework
```

### 3. Add the xcframework to the Xcode project

1. Open `Kraken.xcodeproj` in Xcode.
2. Drag `GhosttyKit.xcframework` into the **Frameworks, Libraries, and Embedded Content** section of the Kraken target.
3. Set it to **Embed & Sign**.

### 4. Build and run

Select the Kraken scheme and hit **Cmd+R**.

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
cd ~/repos/cloned-repos/ghostty/example/swift-vt-xcframework
swift build
swift run
```

This proves the xcframework links and runs independently of Kraken's UI.

## Coding Guidelines

All Swift and SwiftUI code in this project follows the conventions in [`swift_skill.md`](swift_skill.md). Key highlights:

- Use `@Observable` classes (not `ObservableObject`) for shared state.
- Target modern Swift concurrency — `async/await`, not `DispatchQueue`.
- Prefer `foregroundStyle()` over `foregroundColor()`, `clipShape(.rect(cornerRadius:))` over `cornerRadius()`, and `NavigationStack` over `NavigationView`.
- Avoid `GeometryReader` when newer alternatives (`containerRelativeFrame`, `visualEffect`) suffice.
- Do not use `onTapGesture()` unless you need tap location/count — use `Button` instead.

## License

TBD
