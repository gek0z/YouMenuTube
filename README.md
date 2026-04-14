# YouMenuTube

A macOS menu-bar app that puts YouTube in your menubar:

- **Home** (default tab) — YouTube's main recommendations feed
- Latest videos from your **Subscriptions**
- Browse your **Playlists** (including **Watch Later** and **Liked Videos**)
- **Search** YouTube
- **Settings** for default playlist, autoplay, floating-window behaviour,
  hide-Shorts (per feed), and version / update-check info
- Click any video to play it in a chrome-less, 16:9 floating mini player
- In-app **update check** against the latest GitHub release

Built with SwiftUI `MenuBarExtra`, targeting **macOS 15 Sequoia or later**.
Powered by [YouTubeKit](https://github.com/b5i/YouTubeKit) — talks to
YouTube's own internal "InnerTube" API directly. **No Google Cloud project,
no API key, no OAuth client to set up.** Sign into youtube.com in your
usual browser — passkeys, password managers, all of it — and YouMenuTube
imports the session. Supports Safari, Chrome, Edge, Arc, Brave, Vivaldi,
Opera, Helium and Firefox.

> ## ⚠️ Important — read before installing
>
> **YouMenuTube is unofficial and not affiliated with, endorsed by, or
> sponsored by YouTube, Google, or Alphabet.** All trademarks belong to
> their respective owners.
>
> The app authenticates by importing `youtube.com` cookies out of your
> browser's on-disk cookie store (same trick yt-dlp uses), then talks to
> YouTube's internal **InnerTube** API via [YouTubeKit](https://github.com/b5i/YouTubeKit).
> This is the same surface YouTube's own website uses, but it is **not a
> public API** and using it is **arguably outside YouTube's Terms of
> Service**. The API can — and occasionally does — change or break without
> notice.
>
> **Use at your own risk.** Recommendations:
> - Treat this as a personal-use project, not a production tool.
> - Strongly consider using a secondary Google account, not your primary one.
> - Don't expect notifications, video uploads, or anything beyond read-mostly
>   playback / browsing.
> - The maintainers accept no liability for account suspensions, data loss,
>   or anything else (see `LICENSE`).

## Install

1. Grab the latest DMG from the [latest release](https://github.com/gek0z/YouMenuTube/releases/latest)
   (that link permanently redirects to the newest published version, so you
   can bookmark it).
2. Open the DMG and drag `YouMenuTube.app` into `/Applications`.
3. **First launch** — because the build is ad-hoc signed (no paid Apple
   Developer ID), Gatekeeper will refuse it on a normal double-click. Either:
   - Right-click the app → **Open** → **Open** again in the prompt, *or*
   - System Settings → Privacy & Security → "YouMenuTube was blocked …" →
     **Open Anyway**.
4. Subsequent launches work normally.

The app checks `/releases/latest` once per launch (in Settings → About) and
shows an "Update available" link if a newer version is published.

## Project layout

```
YouMenuTube/
├── bootstrap.sh                # One-shot setup: prereqs + project generation
├── project.yml                 # XcodeGen spec → generates YouMenuTube.xcodeproj
├── .swift-format               # swift-format config (line length 120, 4-space)
├── .githooks/pre-commit        # swift-format lint on staged Swift files
├── .github/
│   ├── dependabot.yml          # Monthly grouped updates for SPM + Actions
│   └── workflows/
│       ├── ci.yml              # Lint + build + test (PR-label gated)
│       ├── release.yml         # Builds the DMG on v* tag push
│       ├── auto-tag.yml        # Patch-bumps tag on Sources-bearing pushes
│       └── bump-release.yml    # Manual minor / major bump
├── Sources/
│   ├── Info.plist
│   ├── YouMenuTube.entitlements
│   ├── App/
│   │   ├── YouMenuTubeApp.swift
│   │   └── RootView.swift
│   ├── Services/
│   │   ├── YouTubeService.swift     # one client for everything
│   │   ├── PlayerController.swift
│   │   ├── RefreshTrigger.swift     # shared "user pressed refresh" signal
│   │   ├── UpdateChecker.swift      # polls /releases/latest
│   │   ├── Keychain.swift
│   │   └── BrowserCookieImport/        # Reads youtube.com cookies from the user's browser
│   │       ├── Browser.swift
│   │       ├── BrowserDetector.swift
│   │       ├── BrowserCookieImporter.swift
│   │       ├── SQLiteReader.swift
│   │       ├── FirefoxCookies.swift
│   │       ├── ChromiumCookies.swift
│   │       └── SafariBinaryCookies.swift
│   ├── Models/
│   │   └── YouTubeModels.swift      # VideoEntry, PlaylistEntry
│   ├── Utilities/
│   │   └── Constants.swift          # WindowID, UserAgent, BuiltInPlaylist
│   └── Views/
│       ├── VideoRow.swift           # VideoRow, VideoList, ErrorInline, ThumbnailView
│       ├── VideoFeedList.swift      # Shared load/error/empty/list wrapper
│       ├── HomeFeedView.swift
│       ├── SubscriptionsFeedView.swift
│       ├── PlaylistsView.swift      # API + WL/LL synthetic rows
│       ├── SearchView.swift
│       ├── SettingsView.swift
│       ├── PlayerWindow.swift
│       └── ImportSessionWindow.swift
├── Tests/
│   └── SmokeTests.swift             # Swift Testing target
├── LICENSE                          # Apache 2.0
├── NOTICE                           # Third-party attribution
├── SECURITY.md
├── CONTRIBUTING.md
└── README.md
```

## Setup

```sh
brew install xcodegen   # (if missing — bootstrap.sh will offer to do this for you)
./bootstrap.sh
```

This generates `YouMenuTube.xcodeproj`, resolves `YouTubeKit` via SPM, and
opens Xcode. In Xcode:

1. Pick a signing team (target → **Signing & Capabilities → Team**) — a free
   personal team works.
2. Build & Run (⌘R).
3. There's no Dock icon (by design — `LSUIElement`). Look for the ▶️ icon in
   the menu bar.
4. Click the icon → **Sign in** → pick the browser where you're already
   signed in to youtube.com. First import may ask for a one-time permission
   (see "How sign-in works" below). Session cookies land in the macOS
   Keychain and the window closes.

`bootstrap.sh` flags: `--no-open`, `--clean`.

## How it works

| Feature             | Endpoint (YouTubeKit / InnerTube)         |
|---------------------|-------------------------------------------|
| Home recommendations| `HomeScreenResponse`                      |
| Subscriptions feed  | `AccountSubscriptionsFeedResponse`        |
| Your playlists      | `AccountPlaylistsResponse`                |
| Playlist contents   | `PlaylistInfosResponse` (browseId `VL…`)  |
| Watch Later         | `PlaylistInfosResponse` (browseId `VLWL`) |
| Liked Videos        | `PlaylistInfosResponse` (browseId `VLLL`) |
| Search              | `SearchResponse`                          |

### How sign-in works

YouMenuTube doesn't host a sign-in UI of its own. Instead it imports
`youtube.com` cookies directly out of your browser's cookie store, so the
sign-in itself happens wherever your passkeys / password manager already
work — your normal browser. Three formats covered:

| Browser family | Storage | What macOS will ask |
|---|---|---|
| **Safari** | Binary cookies inside the Safari container | One-time **Full Disk Access** grant (System Settings → Privacy & Security → Full Disk Access → add YouMenuTube). Without it the import fails cleanly. |
| **Chrome / Edge / Arc / Brave / Vivaldi / Opera / Helium** (Chromium family) | SQLite + AES-128-CBC with a key in the login Keychain | A standard "YouMenuTube wants to use confidential information stored in 'Chrome Safe Storage' …" Keychain prompt. Click **Always Allow** once per browser. (Helium's Keychain entry is `Helium Storage Key` rather than the usual `… Safe Storage`, but the flow is identical.) |
| **Firefox** | Plain SQLite, unencrypted | No prompt. |

The importer filters strictly to `*.youtube.com`-scoped rows — mixing in
`.google.com` or `accounts.google.com` cookies makes InnerTube respond
with `loggedOut=true`. The resulting blob is persisted in the macOS
Keychain and handed to YouTubeKit via `YouTubeModel.cookies`.

If your browser isn't signed in to youtube.com yet, the import window
shows a "Sign in to YouTube in [Browser]" button that opens your browser
to `https://www.youtube.com/signin` for you. Come back to YouMenuTube
once signed in and click **Import**.

The Now Playing window wraps `youtube.com/embed/<id>` in a tiny HTML page
loaded with `baseURL = https://youmenutube.local/`. The fake-but-real-looking
parent origin is what makes YouTube's IFrame player initialize — loading
the embed URL top-level returns error 153, and `baseURL = youtube.com`
(same-origin parent) returns 152-4.

The window itself uses `.windowStyle(.plain)` for a fully chrome-less look,
locked to a 16:9 aspect ratio via `NSWindow.aspectRatio`. Because plain
(borderless) windows can't normally become key or be resized, the underlying
`NSWindow`'s styleMask is patched to add `.resizable` — which restores both
edge-resize handles and Cmd+W. A 28pt strip at the top of the player fades
in on hover, hosting a small ✕ close button and a `performDrag(with:)`-backed
draggable region (since the WKWebView itself swallows mouse events). By
default the window floats above other apps; toggle this in Settings.

## Development

| Tool | What | How to run |
|------|------|------------|
| `swift-format` | Format & lint Swift sources | `xcrun swift-format format -i -r --configuration .swift-format Sources Tests` (write) / `... lint --strict ...` (check) |
| Swift Testing | Unit tests under `Tests/` | `xcodebuild ... test` (or ⌘U in Xcode) |
| Pre-commit hook | Runs swift-format lint on staged files | Auto-installed by `bootstrap.sh` (`git config core.hooksPath .githooks`); see `.githooks/pre-commit` |
| GitHub Actions CI | Lint + build + test on `macos-15`. Opt-in only: add the `run-ci` label to a PR (or use the "Run workflow" button) so macOS minutes aren't burned on every push | `.github/workflows/ci.yml` |
| Dependabot | Monthly grouped updates for SPM packages and GitHub Actions | `.github/dependabot.yml` |

Configuration lives in [`.swift-format`](.swift-format) (line length 120, 4-space indent).
See [CONTRIBUTING.md](CONTRIBUTING.md) for PR conventions and detail.

### Releases

Releases are fully automated. The pipeline:

1. **Auto-tag** (`.github/workflows/auto-tag.yml`) — every push to `main` that
   touches `Sources/`, `Tests/`, `project.yml`, or `bootstrap.sh` gets a patch
   bump (e.g. `v0.1.5 → v0.1.6`). Docs / dependabot / hook / format-config
   pushes don't trigger it.
2. **Release** (`.github/workflows/release.yml`) — fires on `v*` tag pushes,
   builds the `.app` (Release config), ad-hoc signs it, packages it as a
   `.dmg` with `create-dmg`, and publishes a GitHub Release.
3. **Bump & Release** (`.github/workflows/bump-release.yml`) — manual entry
   point (Actions tab → Run workflow) for `minor` / `major` bumps. Patches
   are handled by Auto-tag.

Versioning: `CFBundleShortVersionString` is derived from `git describe`
(post-build script in `project.yml`) — `0.1.0` on a tag, `0.1.0+N` past it.
`CFBundleVersion` is `git rev-list --count HEAD` (monotonic, kept for
macOS update bookkeeping even though it isn't shown in UI). `GitCommit`
holds the short SHA (with a `-dirty` suffix when the working tree has
uncommitted changes). Settings → About displays marketing version and
commit, e.g. `0.1.0 · 19d5410`.

## Troubleshooting

- **Import says "Safari's cookies live inside a protected container"** —
  macOS requires **Full Disk Access** to read `~/Library/Containers/com.apple.Safari/…`.
  System Settings → Privacy & Security → Full Disk Access → add YouMenuTube
  (the Import window has a shortcut button for this). Re-run Import.
- **Import says "Couldn't read [Browser]'s cookie-encryption key from the
  Keychain"** — you clicked Deny on the macOS Keychain prompt. Open
  Keychain Access, search for "Safe Storage" for that browser, open the
  entry → **Access Control** tab → remove YouMenuTube from the deny list
  (or delete the ACL), then re-run Import and click **Always Allow**.
- **Import says "[Browser] isn't signed in to YouTube"** — the browser
  you picked doesn't have a valid YouTube session. Click the
  "Sign in to YouTube in [Browser]" button, complete sign-in there, then
  re-run Import.
- **Subscriptions / playlists empty after signing in** — enable verbose
  logging to see what the import produced:
  `log stream --predicate 'subsystem == "app.youmenutube"' --level debug`.
  If session markers (SAPISID, SID, LOGIN_INFO, __Secure-3PSIDTS) are all
  present but InnerTube still says `loggedOut=true`, YouTubeKit may be out
  of date — check for a newer release.
- **Embed player shows error 150 / 101** — the uploader has disabled
  embedding for that specific video; it can only be played on youtube.com.
- **Embed player shows error 153 / 152-4** — should not happen with the
  current wrapper; if it does, check `Sources/Views/PlayerWindow.swift` for
  changes to `baseURL` or the iframe `origin` query parameter.

## Privacy

YouMenuTube runs entirely on your Mac. There is no telemetry, no analytics,
no crash reporting back-channel, no remote config. The app reaches the
network only for:

- YouTube's own InnerTube endpoints for feeds, playlists, and search
- `api.github.com/repos/gek0z/YouMenuTube/releases/latest` once per launch
  to render the update-available link in Settings → About

Sign-in itself happens in your browser, not in YouMenuTube — the app
doesn't make network requests to Google / YouTube for authentication. It
reads `youtube.com` cookies out of your browser's on-disk cookie store
(filtered to `*.youtube.com` only), stores them in the macOS Keychain
under service `com.youmenutube.app`, and uses them as the `Cookie` header
on its own InnerTube requests. Sign out at any time to wipe them
(Settings → Account → Sign out).

## License

YouMenuTube is licensed under the [Apache License 2.0](LICENSE). See
[NOTICE](NOTICE) for third-party attribution.
