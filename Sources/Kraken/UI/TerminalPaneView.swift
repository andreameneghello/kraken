import SwiftUI

/// Detail pane that renders the terminal for the selected zmx session.
struct TerminalPaneView: View {
    let sessionID: String
    let bridge: GhosttyBridge

    var body: some View {
        GeometryReader { geometry in
            TerminalSurfaceRepresentable(
                bridge: bridge,
                size: geometry.size,
                sessionID: sessionID
            )
        }
    }
}
