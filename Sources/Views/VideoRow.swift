import SwiftUI

struct VideoRow: View {
    let entry: VideoEntry
    var onPlay: () -> Void
    @Environment(YouTubeService.self) private var yt

    private var metaLine: String {
        let time = entry.timePosted?.trimmingCharacters(in: .whitespaces)
        let views = entry.viewCount?.trimmingCharacters(in: .whitespaces)
        // YouTube sometimes returns the same string for both fields (or a
        // date string in place of views), so only keep `views` when it
        // actually looks like a view count.
        let viewsLooksReal: Bool = {
            guard let v = views, !v.isEmpty, v.caseInsensitiveCompare(time ?? "") != .orderedSame else {
                return false
            }
            let lower = v.lowercased()
            return lower.contains("view") || lower.contains("watching")
        }()
        let parts = [time, viewsLooksReal ? views : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? " " : parts.joined(separator: " • ")
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 10) {
                ThumbnailView(url: entry.thumbnailURL)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomLeading) {
                        if let duration = entry.duration, !duration.isEmpty {
                            Text(duration)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.75), in: Capsule())
                                .padding(4)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(entry.channelTitle ?? " ")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                if yt.isSignedIn {
                    WatchLaterToggle(videoId: entry.id)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WatchLaterToggle: View {
    let videoId: String
    @Environment(YouTubeService.self) private var yt
    @State private var isWorking = false

    var body: some View {
        let saved = yt.isInWatchLater(videoId)
        Button {
            guard !isWorking else { return }
            Task {
                isWorking = true
                defer { isWorking = false }
                if saved {
                    try? await yt.removeFromWatchLater(videoId: videoId)
                } else {
                    try? await yt.addToWatchLater(videoId: videoId)
                }
            }
        } label: {
            Image(systemName: saved ? "clock.badge.checkmark.fill" : "clock")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(saved ? Color.accentColor : Color.secondary)
                .font(.system(size: 16))
                .opacity(isWorking ? 0.4 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .disabled(isWorking)
        .help(saved ? "Remove from Watch Later" : "Save to Watch Later")
    }
}

struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            case .failure:
                Color.gray.opacity(0.2).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Color.gray.opacity(0.15)
            }
        }
        // Disable the implicit cross-fade, its layout pass jitters LazyVStack
        // when many rows finish loading in quick succession during fast scrolls.
        .transaction { $0.animation = nil }
    }
}

/// Scrollable list of `VideoRow`s with thin dividers. Used by any screen
/// that renders a flat list of videos (home, subscriptions, playlist
/// detail, search).
struct VideoList: View {
    let entries: [VideoEntry]
    let onPlay: (VideoEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    VideoRow(entry: entry) { onPlay(entry) }
                    Divider().opacity(0.3)
                }
            }
        }
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
