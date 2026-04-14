import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, subscriptions, playlists, search, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .subscriptions: "Subscriptions"
        case .playlists: "Playlists"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .subscriptions: "rectangle.stack.badge.play"
        case .playlists: "music.note.list"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(RefreshTrigger.self) private var refresh
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .home

    /// Tabs whose content has a "reload from server" concept. The header
    /// refresh button is hidden on tabs that don't.
    private static let refreshableTabs: Set<Tab> = [.home, .subscriptions, .playlists]

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
        // Close the MenuBarExtra popover so focus can shift to the new
        // window. When the popover stays key, AppKit leaves the newly
        // opened sign-in window behind whatever app was frontmost.
        NSApp.keyWindow?.close()
        openWindow(id: WindowID.signIn)
    }

    private var header: some View {
        HStack(spacing: 8) {
            YouTubeLogo()
            Text("YouMenuTube").font(.headline)
            Spacer()
            if Self.refreshableTabs.contains(tab) {
                Button {
                    refresh.ping()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
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
        // Home + Search + Settings are usable signed-out (Home returns
        // generic suggestions; Search hits the public endpoint).
        let needsSignIn: Set<Tab> = [.subscriptions, .playlists]
        if !yt.isSignedIn && needsSignIn.contains(tab) {
            SignInPlaceholder { presentSignIn() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                switch tab {
                case .home: HomeFeedView()
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

/// Compact YouTube-style mark: white play triangle on a rounded red plate.
private struct YouTubeLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.red)
            Image(systemName: "play.fill")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 13)
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
