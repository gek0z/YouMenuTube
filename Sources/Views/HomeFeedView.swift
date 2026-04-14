import SwiftUI

struct HomeFeedView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(\.openWindow) private var openWindow
    @AppStorage("home.hideShorts") private var hideShorts: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if !yt.isSignedIn {
                SignInBanner {
                    NSApp.keyWindow?.close()
                    openWindow(id: WindowID.signIn)
                }
                Divider()
            }
            VideoFeedList(
                load: { try await yt.homeFeed() },
                include: { !hideShorts || !$0.isShort },
                empty: {
                    ContentUnavailableView(
                        "Nothing to recommend yet",
                        systemImage: "house",
                        description: Text("Watch a few videos to see recommendations here."))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SignInBanner: View {
    var onSignIn: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sign in for a personalized feed")
                    .font(.callout)
                Text("See your subscriptions, playlists, and Watch Later.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign in", action: onSignIn)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
