import AppKit
import GhosttyKit

/// Holds persistent TerminalSurfaceViews per session so Ghostty scrollback
/// survives session switches. Surfaces are destroyed only when the app quits
/// or the session is explicitly killed.
@MainActor
final class SurfaceCache {
    static let shared = SurfaceCache()

    private var surfaces: [String: TerminalSurfaceView] = [:]
    private var killedIDs: Set<String> = []

    /// Retrieve an existing surface for `sessionID`, or create one if needed.
    /// The surface is kept alive in the cache even when not visible.
    func surface(
        for sessionID: String,
        bridge: GhosttyBridge,
        size: CGSize
    ) -> TerminalSurfaceView? {
        // Never recreate a surface for a killed session.
        guard !killedIDs.contains(sessionID) else { return nil }
        if let existing = surfaces[sessionID] {
            existing.sizeDidChange(size)
            return existing
        }

        let view = TerminalSurfaceView(bridge: bridge)
        let command = ZmxController.attachCommand(for: sessionID)
        view.createSurface(command: command)
        view.sizeDidChange(size)
        surfaces[sessionID] = view
        return view
    }

    /// Remove a surface from the cache and destroy its underlying ghostty surface.
    /// Marks the session as killed so it won't be recreated by zmx attach upsert.
    func removeSurface(for sessionID: String) {
        killedIDs.insert(sessionID)
        guard let view = surfaces.removeValue(forKey: sessionID) else { return }
        view.destroySurface()
    }

    /// Allow a previously-killed session to be recreated (user created new session).
    func allowRecreation(for sessionID: String) {
        killedIDs.remove(sessionID)
    }

    /// Destroy every cached surface. Called on app termination.
    func clear() {
        for (_, view) in surfaces {
            view.destroySurface()
        }
        surfaces.removeAll()
        killedIDs.removeAll()
    }
}
