import SwiftUI

@main
struct YouMenuTubeApp: App {
    @State private var yt = YouTubeService()
    @State private var player = PlayerController()
    @State private var refresh = RefreshTrigger()
    @State private var updates = UpdateChecker()
    @State private var dock = DockPresence()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(yt)
                .environment(player)
                .environment(refresh)
                .environment(updates)
                .frame(width: 420, height: 560)
        } label: {
            Image(systemName: "play.rectangle.fill")
        }
        .menuBarExtraStyle(.window)

        Window("Now Playing", id: WindowID.player) {
            PlayerWindow()
                .environment(player)
                .environment(dock)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Import YouTube session", id: WindowID.importSession) {
            ImportSessionWindow()
                .environment(yt)
                .environment(dock)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
