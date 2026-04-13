import SwiftUI

@main
struct YouMenuTubeApp: App {
    @State private var yt = YouTubeService()
    @State private var player = PlayerController()
    @State private var refresh = RefreshTrigger()
    @State private var updates = UpdateChecker()

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
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Sign in to YouTube", id: WindowID.signIn) {
            YouTubeSignInWindow()
                .environment(yt)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
