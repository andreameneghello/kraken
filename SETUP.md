# Kraken — Setup Guide

## Prerequisites

- **macOS 14+**
- **Xcode 16+** (required to build `GhosttyKit.xcframework` — the ~10 GB download from the App Store or [Apple Developer](https://developer.apple.com/download/))
- **Zig 0.15.x** (`brew install zig@0.15`)

> ⚠️ Command Line Tools alone are **not enough**. Ghostty's xcframework includes iOS simulator slices, and the iOS SDK only ships with the full Xcode app.

## 1. Build GhosttyKit.xcframework

```bash
# Ensure Zig 0.15 is on PATH
export PATH="/opt/homebrew/opt/zig@0.15/bin:$PATH"

# Build the xcframework
cd ~/repos/cloned-repos/ghostty
zig build -Demit-xcframework
```

This produces:
```
ghostty/zig-out/lib/GhosttyKit.xcframework
```

Copy it into the Kraken project:
```bash
cp -R ~/repos/cloned-repos/ghostty/zig-out/lib/GhosttyKit.xcframework \
      ~/repos/kraken/Frameworks/
```

## 2. Open the project in Xcode

1. Open **Xcode**.
2. Choose **File → Open** and select `~/repos/kraken/Package.swift`.
   Xcode will create an auto-generated project from the Swift Package.
3. In the project navigator, select the **Kraken** target.
4. Under **Frameworks, Libraries, and Embedded Content**, ensure `GhosttyKit.xcframework` is listed and set to **Embed & Sign**.

> If `GhosttyKit.xcframework` does not appear automatically, drag it from the `Frameworks/` folder into the target's "Frameworks, Libraries, and Embedded Content" section.

## 3. Build and run

Select the **Kraken** scheme and press **Cmd+R**.

You should see a terminal window with your default shell prompt.

## Troubleshooting

### `DarwinSdkNotFound` during `zig build`

You do not have Xcode installed, or `xcode-select` is pointing to Command Line Tools only. Run:
```bash
sudo xcode-select --switch /Applications/Xcode.app
```

### Blank terminal surface

- Verify `GhosttyKit.xcframework` is embedded (not just linked).
- Check that `TerminalSurfaceView.wantsLayer = true`.
- Confirm Metal is available on your Mac (all Apple Silicon and recent Intel Macs support it).

### Keyboard input not reaching the terminal

- Ensure the view has focus (click inside the window).
- Check the Xcode console for `ghostty_surface_key` errors.

### Xcode cannot find `ghostty.h`

The C API is exposed through the `GhosttyKit` module map inside the xcframework. You do not need to add `include/ghostty.h` to header search paths manually — `import GhosttyKit` is sufficient.
