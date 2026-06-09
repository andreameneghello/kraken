import AppKit
import GhosttyKit

/// An `NSView` subclass that hosts a single libghostty terminal surface.
///
/// The view forwards keyboard and mouse events to the C core and reports
/// size / backing-scale changes so the terminal renders correctly.
@MainActor
final class TerminalSurfaceView: NSView {
    nonisolated(unsafe) private var surface: ghostty_surface_t?
    private let bridge: GhosttyBridge

    /// Package-internal access for clipboard callbacks.
    nonisolated var ghosttySurface: ghostty_surface_t? { surface }

    init(bridge: GhosttyBridge) {
        self.bridge = bridge
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    /// Create the underlying `ghostty_surface_t`.
    func createSurface(command: String? = nil) {
        surface = bridge.createSurface(for: self, command: command)
    }

    /// Destroy the underlying surface.
    func destroySurface() {
        guard let surface else { return }
        ghostty_surface_free(surface)
        self.surface = nil
    }

    /// Report a new content size (in points) to the terminal core.
    func sizeDidChange(_ size: CGSize) {
        guard let surface else { return }
        // Guard against zero dimensions — Ghostty's terminal code
        // overflows when allocating zero columns/rows.
        guard size.width > 0, size.height > 0 else { return }
        let scaled = convertToBacking(NSRect(origin: .zero, size: size)).size
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    // MARK: - NSView overrides

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface else { return }
        let fbFrame = convertToBacking(frame)
        let xScale = fbFrame.size.width / frame.size.width
        let yScale = fbFrame.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard surface != nil else { return nil }
        guard event.type == .rightMouseDown else { return nil }

        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Reset Terminal", action: #selector(resetTerminal(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Change Title…", action: #selector(promptTitle(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func copy(_ sender: Any?) {
        guard let surface else { return }
        let action = "copy_to_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    @objc private func paste(_ sender: Any?) {
        guard let surface else { return }
        let action = "paste_from_clipboard"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    @objc override func selectAll(_ sender: Any?) {
        guard let surface else { return }
        let action = "select_all"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    @objc private func resetTerminal(_ sender: Any?) {
        guard let surface else { return }
        let action = "reset"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    @objc private func promptTitle(_ sender: Any?) {
        guard let surface else { return }
        let action = "prompt_title"
        _ = ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        guard let surface else { return }
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else {
            super.rightMouseDown(with: event)
            return
        }
        let mods = ghosttyMods(event.modifierFlags)
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else {
            super.rightMouseUp(with: event)
            return
        }
        let mods = ghosttyMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
        super.rightMouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }
        ghostty_surface_mouse_scroll(surface, x, y, 0)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            super.keyDown(with: event)
            return
        }

        // Intercept Cmd+key shortcuts before sending to Ghostty.
        if event.modifierFlags.contains(.command) {
            if handleCommandKey(event, surface: surface) {
                return
            }
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        sendKeyEvent(event, action: action, to: surface)
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }
        sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE, to: surface)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier-only changes don't need to be sent to the terminal.
    }

    // MARK: - Private

    /// Handle Cmd+key bindings. Returns true if consumed.
    private func handleCommandKey(_ event: NSEvent, surface: ghostty_surface_t) -> Bool {
        switch event.keyCode {
        case 8: // c
            let action = "copy_to_clipboard"
            return ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
        case 9: // v
            let action = "paste_from_clipboard"
            return ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
        case 0: // a
            let action = "select_all"
            return ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
        default:
            return false
        }
    }

    private func sendKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        to surface: ghostty_surface_t
    ) {
        let text = event.ghosttyCharacters
        let consumedMods = event.modifierFlags.subtracting([.control, .command])

        if let text, !text.isEmpty {
            text.withCString { textPtr in
                var keyEv = ghostty_input_key_s()
                keyEv.action = action
                keyEv.keycode = UInt32(event.keyCode)
                keyEv.mods = ghosttyMods(event.modifierFlags)
                keyEv.consumed_mods = ghosttyMods(consumedMods)
                keyEv.text = textPtr
                keyEv.composing = false
                keyEv.unshifted_codepoint = event.unshiftedCodepoint
                _ = ghostty_surface_key(surface, keyEv)
            }
        } else {
            var keyEv = ghostty_input_key_s()
            keyEv.action = action
            keyEv.keycode = UInt32(event.keyCode)
            keyEv.mods = ghosttyMods(event.modifierFlags)
            keyEv.consumed_mods = ghosttyMods(consumedMods)
            keyEv.text = nil
            keyEv.composing = false
            keyEv.unshifted_codepoint = event.unshiftedCodepoint
            _ = ghostty_surface_key(surface, keyEv)
        }
    }
}
