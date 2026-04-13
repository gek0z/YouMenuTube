import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case subscriptions, playlists, search, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptions: "Subscriptions"
        case .playlists: "Playlists"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .subscriptions: "rectangle.stack.badge.play"
        case .playlists: "music.note.list"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .subscriptions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            tabBar
        }
        .background(.ultraThinMaterial)
    }

    private func presentSignIn() {
        openWindow(id: "youtube-signin")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
            Text("YouMenuTube").font(.headline)
            Spacer()
            if !yt.isSignedIn {
                Button {
                    presentSignIn()
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !yt.isSignedIn && tab != .settings {
            SignInPlaceholder { presentSignIn() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                switch tab {
                case .subscriptions: SubscriptionsFeedView()
                case .playlists: PlaylistsView()
                case .search: SearchView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.systemImage)
                        Text(t.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct SignInPlaceholder: View {
    @Environment(YouTubeService.self) private var yt
    var onSignIn: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Sign in to YouTube to see your subscriptions, playlists, and search.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button(action: onSignIn) {
                Label("Sign in", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            if let err = yt.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
    }
}
