import SwiftUI

/// Loads `[VideoEntry]` via the supplied async closure and renders the
/// usual loading / error / empty / list states. Re-fetches whenever the
/// shared `RefreshTrigger` bumps.
struct VideoFeedList<Empty: View>: View {
    let load: () async throws -> [VideoEntry]
    var include: (VideoEntry) -> Bool = { _ in true }
    @ViewBuilder let empty: () -> Empty

    @Environment(PlayerController.self) private var player
    @Environment(RefreshTrigger.self) private var refresh
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        let visible = entries.filter(include)
        Group {
            if let error {
                ErrorInline(message: error) { Task { await reload() } }
            } else if isLoading && visible.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                empty()
            } else {
                VideoList(entries: visible) { entry in
                    player.play(videoId: entry.id, title: entry.title)
                    openWindow(id: WindowID.player)
                }
            }
        }
        .task(id: refresh.counter) { await reload() }
    }

    private func reload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { entries = try await load() } catch { self.error = error.localizedDescription }
    }
}
