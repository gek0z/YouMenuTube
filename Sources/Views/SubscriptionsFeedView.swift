import SwiftUI

struct SubscriptionsFeedView: View {
    @Environment(YouTubeService.self) private var yt
    @AppStorage("subscriptions.hideShorts") private var hideShorts: Bool = true

    var body: some View {
        VideoFeedList(
            load: { try await yt.subscriptionsFeed() },
            include: { !hideShorts || !$0.isShort },
            empty: {
                ContentUnavailableView(
                    "No recent videos",
                    systemImage: "rectangle.stack.badge.play",
                    description: Text("Subscribe to a few channels to see their latest uploads."))
            }
        )
    }
}
