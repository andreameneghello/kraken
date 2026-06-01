import AppKit
import SwiftUI

class KrakenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Entry point for the Kraken macOS app.
@main
@MainActor
struct KrakenApp: App {
    @NSApplicationDelegateAdaptor(KrakenAppDelegate.self) private var appDelegate
    @State private var bridge = GhosttyBridge()
    @AppStorage("recentSessionDirectories") private var recentDirsData = Data()

    private var recentDirectories: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: recentDirsData)) ?? []
        }
        nonmutating set {
            recentDirsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(bridge)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kraken") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
            CommandGroup(after: .newItem) {
                Button("Open Session...") {
                    openSession()
                }
                .keyboardShortcut("o", modifiers: .command)

                if !recentDirectories.isEmpty {
                    Divider()
                    ForEach(recentDirectories.prefix(5), id: \.self) { dir in
                        Button("Open Recent: \(URL(fileURLWithPath: dir).lastPathComponent)") {
                            openRecentSession(directory: dir)
                        }
                    }
                    Divider()
                    Button("Clear Recent") {
                        recentDirectories = []
                    }
                }
            }
        }
    }

    private func openSession() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory for the new session"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let dir = url.path
        let name = url.lastPathComponent
        createSessionInDirectory(name: name, directory: dir)
    }

    private func openRecentSession(directory: String) {
        let name = URL(fileURLWithPath: directory).lastPathComponent
        createSessionInDirectory(name: name, directory: directory)
    }

    private func createSessionInDirectory(name: String, directory: String) {
        let tmux = TmuxController()
        let success = tmux.createSession(name: name, directory: directory)
        guard success else { return }

        // Track recent directory
        var recent = recentDirectories
        recent.removeAll { $0 == directory }
        recent.insert(directory, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        recentDirectories = recent
    }
}
