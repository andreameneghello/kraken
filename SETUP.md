# Kraken — Setup Guide

## Prerequisites

- macOS 14+
- Xcode 16+ (for building GhosttyKit.xcframework)
- Zig 0.15.x (`brew install zig@0.15`)
- zmx (`brew install neurosnap/tap/zmx` or download from https://zmx.sh)

## 1. Build GhosttyKit.xcframework

```bash
export PATH="/opt/homebrew/opt/zig@0.15/bin:$PATH"
cd /path/to/ghostty
zig build -Demit-xcframework
cp -R zig-out/lib/GhosttyKit.xcframework /path/to/kraken/Frameworks/
```

## 2. Build

```bash
cd kraken
make run       # debug build, runs immediately
make bundle    # release .app bundle
make install   # install to ~/Applications/
```

## Troubleshooting

### `zmx: command not found`

Install zmx: `brew install neurosnap/tap/zmx` or place the binary at `/opt/homebrew/bin/zmx`.

### Blank terminal surface

- Verify `GhosttyKit.xcframework` exists in `Frameworks/`
- Check zmx logs: `tail -f /tmp/krkn/logs/zmx.log`
- Verify session exists: `ZMX_DIR=/tmp/krkn zmx list --short`

### Session not appearing in sidebar

The sidebar polls zmx every 2 seconds. Ensure `ZMX_DIR` matches across all processes (set to `/tmp/krkn`).

### Crash on surface creation

Check for zero-size resize (guarded in `TerminalSurfaceView.sizeDidChange`). If Ghostty crashes with `integer overflow`, the surface received invalid dimensions.
