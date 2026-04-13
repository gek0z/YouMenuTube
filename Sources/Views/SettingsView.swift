import SwiftUI

struct SettingsView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(UpdateChecker.self) private var updates
    @AppStorage("player.autoplay") private var autoplay: Bool = true
    @AppStorage("player.floatOnTop") private var floatOnTop: Bool = true
    @AppStorage("subscriptions.hideShorts") private var hideShorts: Bool = true
    @AppStorage("home.hideShorts") private var hideHomeShorts: Bool = true
    @AppStorage("playlists.pinnedId") private var pinnedId: String = ""
    @AppStorage("playlists.pinnedTitle") private var pinnedTitle: String = ""

    @State private var playlists: [PlaylistEntry] = []
    @State private var loadingPlaylists = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Image(
                        systemName: yt.isSignedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark"
                    )
                    .foregroundStyle(yt.isSignedIn ? .green : .orange)
                    Text(yt.isSignedIn ? "Signed in to YouTube" : "Not signed in")
                    Spacer()
                    if yt.isSignedIn {
                        Button("Sign out", role: .destructive) { yt.signOut() }
                            .controlSize(.small)
                    } else {
                        Button("Sign in") { openWindow(id: "youtube-signin") }
                            .controlSize(.small)
                    }
                }
                Text(
                    "Uses YouTube's own internal API via your browser session — no Google Cloud setup needed. Personal use only."
                )
                .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Pinned playlist") {
                if yt.isSignedIn {
                    HStack {
                        Picker("Default playlist", selection: pinnedSelection) {
                            Text("None").tag(Optional<String>.none)
                            Text("Watch Later").tag(Optional("VLWL"))
                            Text("Liked Videos").tag(Optional("VLLL"))
                            if !playlists.isEmpty {
                                Divider()
                                ForEach(playlists) { p in
                                    Text(p.title).tag(Optional(p.id))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        if loadingPlaylists { ProgressView().controlSize(.small) }
                    }
                    Text("Opens directly when you tap the Playlists tab.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Sign in to choose a default playlist.").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Player") {
                Toggle("Autoplay when opening a video", isOn: $autoplay)
                Toggle("Keep player window floating on top", isOn: $floatOnTop)
            }

            Section("Feeds") {
                Toggle("Hide Shorts in Home", isOn: $hideHomeShorts)
                Toggle("Hide Shorts in Subscriptions", isOn: $hideShorts)
            }

            Section("About") {
                LabeledContent("Version", value: versionDisplay)
                updateRow
            }

            if let err = yt.lastError {
                Section("Diagnostic") {
                    Text(err)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: yt.isSignedIn) {
            guard yt.isSignedIn, playlists.isEmpty else { return }
            loadingPlaylists = true
            defer { loadingPlaylists = false }
            do { playlists = try await yt.myPlaylists() } catch { /* picker just stays empty */  }
        }
        .task { await updates.check() }
    }

    private var versionDisplay: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let commit = (info["GitCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let dev = (info["IsDevBuild"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var head = short
        if let dev { head += " (\(dev))" }
        if let commit, commit != build {
            return "\(head) — \(build) · \(commit)"
        }
        return "\(head) — \(build)"
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updates.state {
        case .idle, .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .upToDate:
            Label("You're on the latest release.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        case .noPublishedRelease:
            Label("No published release to compare against yet.", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        case .available(let version, let url):
            Link(destination: url) {
                Label("Update available: \(version)", systemImage: "arrow.down.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .font(.caption)
        case .failed(let why):
            Label("Update check failed: \(why)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var pinnedSelection: Binding<String?> {
        Binding(
            get: {
                switch pinnedId {
                case "": return nil
                case "WL": return "VLWL"  // migrate legacy stored values
                case "LL": return "VLLL"
                default: return pinnedId
                }
            },
            set: { newValue in
                switch newValue {
                case nil:
                    pinnedId = ""
                    pinnedTitle = ""
                case "VLWL":
                    pinnedId = "VLWL"
                    pinnedTitle = "Watch Later"
                case "VLLL":
                    pinnedId = "VLLL"
                    pinnedTitle = "Liked Videos"
                case .some(let id):
                    pinnedId = id
                    pinnedTitle = playlists.first(where: { $0.id == id })?.title ?? ""
                }
            }
        )
    }
}
