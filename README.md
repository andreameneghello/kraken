# Kraken

Native macOS terminal session orchestrator.

## What it does

Kraken manages persistent terminal sessions inside a native macOS sidebar. Each session runs in a real embedded terminal powered by libghostty. Sessions survive app restarts via zmx, a minimal session persistence daemon.

## Architecture

| Layer | Technology |
|-------|-----------|
| UI | Swift + SwiftUI (`NavigationSplitView`) |
| Terminal | libghostty (C API, Metal renderer) |
| Session persistence | [zmx](https://github.com/neurosnap/zmx) (session daemon + libghostty-vt state restore) |
| Build | Swift Package Manager + Makefile |

```
Kraken.app
├── SwiftUI sidebar        ← session list, search, create/kill
├── Ghostty terminal view  ← zmx attach <session>
├── SurfaceCache           ← hide/show surfaces, preserve scrollback
├── ZmxController           ← zmx CLI wrapper (list, kill, attach, run, send)
└── /tmp/krkn/             ← zmx socket directory (ZMX_DIR)
```

## Project Structure

```
Kraken/
├── App/              — Entry point, app lifecycle
├── Core/             — GhosttyBridge, ZmxController, SurfaceCache
├── UI/               — Sidebar, terminal pane, surface representable
├── Model/            — Session model, SessionStore (polling)
└── Helpers/          — NSEvent extensions
```

## Setup

### Prerequisites

- macOS 14+
- [zmx](https://zmx.sh) — `brew install neurosnap/tap/zmx` or download binary from zmx.sh
- GhosttyKit.xcframework (see below)

### 1. Build GhosttyKit.xcframework

```bash
cd /path/to/ghostty
zig build -Demit-xcframework
cp -R zig-out/lib/GhosttyKit.xcframework /path/to/kraken/Frameworks/
```

Requires Zig 0.15.x (`brew install zig@0.15`) and Xcode 16+.

### 2. Build and run

```bash
cd kraken
make run          # debug build, runs immediately
make bundle       # release .app in Kraken.app/
make install      # installs to ~/Applications/Kraken.app
```

## Usage

- **New session**: click `+` in sidebar, enter a name
- **Kill session**: select it, click trash icon
- **Switch sessions**: click in sidebar — surfaces persist, scrollback intact
- **Dynamic groups**: sidebar groups by live working directory (updates when you `cd`)

## Debugging

### zmx logs

```bash
tail -f /tmp/krkn/logs/zmx.log              # global
tail -f /tmp/krkn/logs/<session-name>.log   # per-session
```

### List zmx sessions directly

```bash
ZMX_DIR=/tmp/krkn zmx list --short
ZMX_DIR=/tmp/krkn zmx attach <name>    # reattach manually
ZMX_DIR=/tmp/krkn zmx kill <name>      # force kill
```

### Reset state

```bash
rm -rf /tmp/krkn
```

## License

[MIT](LICENSE)
