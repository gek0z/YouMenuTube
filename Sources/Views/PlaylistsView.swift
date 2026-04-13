import SwiftUI

private let watchLaterId = "VLWL"
private let likedVideosId = "VLLL"

struct PlaylistsView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @AppStorage("playlists.pinnedId")    private var pinnedId: String = ""
    @AppStorage("playlists.pinnedTitle") private var pinnedTitle: String = ""

    @State private var playlists: [PlaylistEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selected: PlaylistEntry?
    @State private var appliedPinOnAppear = false

    var body: some View {
        Group {
            if let selected {
                PlaylistDetailView(playlist: selected) { self.selected = nil }
            } else {
                list
            }
        }
        .onAppear {
            migrateLegacyPinId()
            guard !appliedPinOnAppear else { return }
            appliedPinOnAppear = true
            if selected == nil, !pinnedId.isEmpty {
                selected = PlaylistEntry(id: pinnedId,
                                         title: pinnedTitle.isEmpty ? "Pinned" : pinnedTitle,
                                         videoCount: nil,
                                         thumbnailURL: nil)
            }
        }
    }

    /// Values saved before the switch to YouTubeKit were stored as raw "WL"
    /// / "LL" — YouTubeKit wants them VL-prefixed.
    private func migrateLegacyPinId() {
        switch pinnedId {
        case "WL": pinnedId = watchLaterId
        case "LL": pinnedId = likedVideosId
        default: break
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Playlists").font(.subheadline.weight(.semibold))
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            if let error {
                ErrorInline(message: error) { Task { await load() } }
            } else if isLoading && playlists.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        syntheticRow(id: watchLaterId, title: "Watch Later", system: "clock")
                        Divider().opacity(0.3)
                        syntheticRow(id: likedVideosId, title: "Liked Videos", system: "hand.thumbsup")
                        Divider().opacity(0.3)
                        ForEach(playlists) { p in
                            row(p)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .task { if playlists.isEmpty { await load() } }
    }

    private func row(_ p: PlaylistEntry) -> some View {
        HStack(spacing: 10) {
            ThumbnailView(url: p.thumbnailURL)
                .frame(width: 72, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let n = p.videoCount {
                    Text("\(n) videos").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            pinButton(id: p.id, title: p.title)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { selected = p }
    }

    private func syntheticRow(id: String, title: String, system: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                Image(systemName: system).foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text("Built-in").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            pinButton(id: id, title: title)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selected = PlaylistEntry(id: id, title: title, videoCount: nil, thumbnailURL: nil)
        }
    }

    private func pinButton(id: String, title: String) -> some View {
        Button {
            if pinnedId == id {
                pinnedId = ""; pinnedTitle = ""
            } else {
                pinnedId = id; pinnedTitle = title
            }
        } label: {
            Image(systemName: pinnedId == id ? "pin.fill" : "pin")
                .foregroundStyle(pinnedId == id ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(pinnedId == id ? "Unpin" : "Pin as default")
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { playlists = try await yt.myPlaylists() }
        catch { self.error = error.localizedDescription }
    }
}

struct PlaylistDetailView: View {
    let playlist: PlaylistEntry
    var onBack: () -> Void

    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @Environment(\.openWindow) private var openWindow
    @State private var items: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)

            if let error {
                ErrorInline(message: error) { Task { await load() } }
            } else if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("Empty playlist",
                                       systemImage: "music.note.list",
                                       description: Text("No videos in this playlist."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { entry in
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
        .task { await load() }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { items = try await yt.playlistItems(playlistId: playlist.id) }
        catch { self.error = error.localizedDescription }
    }
}
