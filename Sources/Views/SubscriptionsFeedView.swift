import SwiftUI

struct SubscriptionsFeedView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @State private var entries: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Latest from Subscriptions").font(.subheadline.weight(.semibold))
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            if let error {
                ErrorInline(message: error) { Task { await load() } }
            } else if isLoading && entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView("No recent videos",
                                       systemImage: "rectangle.stack.badge.play",
                                       description: Text("Subscribe to a few channels to see their latest uploads."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            VideoRow(entry: entry) { player.play(videoId: entry.id, title: entry.title) }
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .task { if entries.isEmpty { await load() } }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { entries = try await yt.subscriptionsFeed() }
        catch { self.error = error.localizedDescription }
    }
}

struct ErrorInline: View {
    let message: String
    var onRetry: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Retry", action: onRetry).controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
