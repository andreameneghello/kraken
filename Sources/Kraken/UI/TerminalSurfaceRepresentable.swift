import SwiftUI

/// SwiftUI bridge that wraps `TerminalSurfaceView`.
///
/// Uses a `Coordinator` to track the current command. When the command
/// changes (session switch) the old surface is destroyed and a new one is
/// created on the same NSView, avoiding expensive NSView destruction.
struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let bridge: GhosttyBridge
    let size: CGSize
    let command: String?

    func makeNSView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(bridge: bridge)
        view.createSurface(command: command)
        view.sizeDidChange(size)
        bridge.appTick()
        context.coordinator.lastCommand = command
        // Ensure focus lands on the new surface.
        Task { @MainActor in
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: TerminalSurfaceView, context: Context) {
        if context.coordinator.lastCommand != command {
            view.destroySurface()
            view.createSurface(command: command)
            context.coordinator.lastCommand = command
            Task { @MainActor in
                view.window?.makeFirstResponder(view)
            }
        }
        view.sizeDidChange(size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCommand: String?
    }
}
