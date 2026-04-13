import SwiftUI

struct HomeFeedView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @Environment(RefreshTrigger.self) private var refresh
    @Environment(\.openWindow) private var openWindow
    @AppStorage("home.hideShorts") private var hideShorts: Bool = true
    @State private var entries: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?

    private var visibleEntries: [VideoEntry] {
        hideShorts ? entries.filter { !$0.isShort } : entries
    }

    var body: some View {
        Group {
            if let error {
                ErrorInline(message: error) { Task { await load() } }
            } else if isLoading && visibleEntries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                ContentUnavailableView(
                    "Nothing to recommend yet",
                    systemImage: "house",
                    description: Text("Watch a few videos to see recommendations here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            VideoRow(entry: entry) {
                                player.play(videoId: entry.id, title: entry.title)
                                openWindow(id: "player")
                            }
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .task(id: refresh.counter) { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { entries = try await yt.homeFeed() } catch { self.error = error.localizedDescription }
    }
}
