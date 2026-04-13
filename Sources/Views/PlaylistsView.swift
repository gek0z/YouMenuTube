import SwiftUI

struct PlaylistsView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(RefreshTrigger.self) private var refresh
    @AppStorage("playlists.pinnedId") private var pinnedId: String = ""
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
            if let migrated = BuiltInPlaylist.migrated(pinnedId) { pinnedId = migrated }
            guard !appliedPinOnAppear else { return }
            appliedPinOnAppear = true
            if selected == nil, !pinnedId.isEmpty {
                selected = PlaylistEntry(
                    id: pinnedId,
                    title: pinnedTitle.isEmpty ? "Pinned" : pinnedTitle,
                    videoCount: nil,
                    thumbnailURL: nil)
            }
        }
    }

    /// `myPlaylists()` returns Watch Later and Liked Videos as ordinary
    /// playlists too. Drop them so they don't render twice alongside the
    /// synthetic built-in rows.
    private func isUserPlaylist(_ p: PlaylistEntry) -> Bool {
        if BuiltInPlaylist.allIds.contains(p.id) { return false }
        let title = p.title.lowercased()
        return title != "watch later" && title != "liked videos"
    }

    private var list: some View {
        Group {
            if let error {
                ErrorInline(message: error) { Task { await load() } }
            } else if isLoading && playlists.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        syntheticRow(id: BuiltInPlaylist.watchLater, title: "Watch Later", system: "clock")
                        Divider().opacity(0.3)
                        syntheticRow(id: BuiltInPlaylist.likedVideos, title: "Liked Videos", system: "hand.thumbsup")
                        Divider().opacity(0.3)
                        ForEach(playlists.filter(isUserPlaylist)) { p in
                            row(p)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .task(id: refresh.counter) { await load() }
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
                pinnedId = ""
                pinnedTitle = ""
            } else {
                pinnedId = id
                pinnedTitle = title
            }
        } label: {
            Image(systemName: pinnedId == id ? "pin.fill" : "pin")
                .foregroundStyle(pinnedId == id ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(pinnedId == id ? "Unpin" : "Pin as default")
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { playlists = try await yt.myPlaylists() } catch { self.error = error.localizedDescription }
    }
}

struct PlaylistDetailView: View {
    let playlist: PlaylistEntry
    var onBack: () -> Void

    @Environment(YouTubeService.self) private var yt

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)

            VideoFeedList(
                load: { try await yt.playlistItems(playlistId: playlist.id) }
            ) {
                ContentUnavailableView(
                    "Empty playlist",
                    systemImage: "music.note.list",
                    description: Text("No videos in this playlist."))
            }
        }
    }
}
