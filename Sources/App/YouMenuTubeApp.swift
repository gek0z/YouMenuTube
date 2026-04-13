import SwiftUI

@main
struct YouMenuTubeApp: App {
    @State private var yt = YouTubeService()
    @State private var player = PlayerController()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(yt)
                .environment(player)
                .frame(width: 420, height: 560)
        } label: {
            Image(systemName: "play.rectangle.fill")
        }
        .menuBarExtraStyle(.window)

        Window("Now Playing", id: "player") {
            PlayerWindow()
                .environment(player)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Sign in to YouTube", id: "youtube-signin") {
            YouTubeSignInWindow()
                .environment(yt)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

