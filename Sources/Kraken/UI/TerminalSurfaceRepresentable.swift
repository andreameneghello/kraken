import SwiftUI

/// SwiftUI bridge that wraps a container NSView holding a cached
/// TerminalSurfaceView per session.
///
/// Instead of destroying and recreating surfaces on session switches, this
/// representable swaps subviews from the SurfaceCache. This keeps Ghostty's
/// scrollback buffer alive, giving native smooth scrolling across switches.
///
/// The container defers surface creation until it has valid dimensions,
/// preventing Ghostty from rendering at default 80 columns.
struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let bridge: GhosttyBridge
    let size: CGSize
    let sessionID: String

    func makeNSView(context: Context) -> NSView {
        let container = SurfaceContainer()
        container.wantsLayer = true
        container.onReady = { [weak container] size in
            guard let container else { return }
            context.coordinator.updateSurface(in: container, bridge: bridge, sessionID: sessionID)
        }
        bridge.appTick()
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let container = container as? SurfaceContainer else { return }
        if context.coordinator.lastSessionID != sessionID {
            // Session changed — swap the surface.
            context.coordinator.updateSurface(in: container, bridge: bridge, sessionID: sessionID)
            context.coordinator.lastSessionID = sessionID
        }
        // Resize the currently displayed surface to fill the container.
        if let surface = container.subviews.first as? TerminalSurfaceView {
            surface.frame = container.bounds
            surface.sizeDidChange(container.bounds.size)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastSessionID: String?

        /// Swap the container's subview to the cached surface for `sessionID`.
        @MainActor
        fileprivate func updateSurface(in container: NSView, bridge: GhosttyBridge, sessionID: String) {
            // Guard: valid dimensions required for correct terminal sizing.
            guard container.bounds.size.width > 0, container.bounds.size.height > 0 else { return }

            // Remove the previous surface (it stays alive in the cache).
            container.subviews.forEach { $0.removeFromSuperview() }

            // Get or create the surface for this session.
            // Returns nil if the session was killed (prevents zmx attach upsert).
            guard let surface = SurfaceCache.shared.surface(
                for: sessionID,
                bridge: bridge,
                size: container.bounds.size
            ) else { return }
            surface.frame = container.bounds
            surface.autoresizingMask = [.width, .height]
            container.addSubview(surface)

            // Ensure the surface receives focus.
            Task { @MainActor in
                surface.window?.makeFirstResponder(surface)
            }
        }
    }
}

/// Container that defers surface creation until it has a valid frame size.
/// Prevents Ghostty from creating a terminal at default 80 columns.
private final class SurfaceContainer: NSView {
    var onReady: ((CGSize) -> Void)?
    private var ready = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !ready, newSize.width > 0, newSize.height > 0 {
            ready = true
            onReady?(newSize)
        }
    }
}
