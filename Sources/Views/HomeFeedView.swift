import SwiftUI

struct HomeFeedView: View {
    @Environment(YouTubeService.self) private var yt
    @AppStorage("home.hideShorts") private var hideShorts: Bool = true

    var body: some View {
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
    }
}
