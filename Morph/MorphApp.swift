import SwiftUI

@main
struct MorphApp: App {
    @AppStorage("appIcon") private var icon = appIcons[0].asset

    var body: some Scene {
        WindowGroup {
            ContentView()
                // A rebuild replaces the bundle and its custom icon; put the picked one back.
                .onAppear {
                    // A pick from a removed icon set falls back to the default.
                    if !appIcons.contains(where: { $0.asset == icon }) { icon = appIcons[0].asset }
                    applyAppIcon(icon)
                }
        }
        .windowResizability(.contentSize)
        // The default cascades from the top left; open the welcome screen in the middle instead.
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
        }

        Window("Morph hakkında", id: "about") { AboutView() }
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)
            .defaultWindowPlacement { _, _ in WindowPlacement(.center) }

        Settings { SettingsView() }
            // Content-sized: otherwise the window keeps a remembered/default width and the grid floats in it.
            .windowResizability(.contentSize)
    }
}

/// Commands can't read openWindow themselves; a tiny view can.
private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Morph hakkında") { openWindow(id: "about") }
    }
}
