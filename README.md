# YouMenuTube

A macOS menu-bar app that puts YouTube in your menubar:

- Sign in with your YouTube account
- Latest videos from your **Subscriptions**
- Browse your **Playlists** (including **Watch Later** and **Liked Videos**)
- **Search** YouTube
- **Settings** for default playlist & playback
- Click any video to play it in an embedded mini player

Built with SwiftUI `MenuBarExtra`, targeting **macOS 15 Sequoia or later**.
Powered by [YouTubeKit](https://github.com/b5i/YouTubeKit) — talks to
YouTube's own internal "InnerTube" API directly. **No Google Cloud project,
no API key, no OAuth client to set up.** You sign into youtube.com once
inside the app and you're done.

> **Heads-up.** InnerTube is YouTube's *unofficial, internal* API. It can
> change without notice and using it isn't strictly within YouTube's ToS —
> intended for personal use.

## Project layout

```
YouMenuTube/
├── bootstrap.sh                # One-shot setup: prereqs + project generation
├── project.yml                 # XcodeGen spec → generates YouMenuTube.xcodeproj
├── Sources/
│   ├── Info.plist
│   ├── YouMenuTube.entitlements
│   ├── App/
│   │   ├── YouMenuTubeApp.swift
│   │   └── RootView.swift
│   ├── Services/
│   │   ├── YouTubeService.swift     # one client for everything
│   │   ├── PlayerController.swift
│   │   └── Keychain.swift
│   ├── Models/
│   │   └── YouTubeModels.swift      # VideoEntry, PlaylistEntry
│   └── Views/
│       ├── VideoRow.swift
│       ├── SubscriptionsFeedView.swift
│       ├── PlaylistsView.swift      # API + WL/LL synthetic rows
│       ├── SearchView.swift
│       ├── SettingsView.swift
│       ├── PlayerWindow.swift
│       └── YouTubeSignInSheet.swift
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
4. Click the icon → **Sign in** → log in to youtube.com inside the sheet. As
   soon as the page lands back on `youtube.com`, the sheet auto-captures the
   session cookies (stored in the macOS Keychain) and closes itself. You can
   also click **Done** manually.

`bootstrap.sh` flags: `--no-open`, `--clean`.

## How it works

| Feature             | Endpoint (YouTubeKit / InnerTube)         |
|---------------------|-------------------------------------------|
| Subscriptions feed  | `AccountSubscriptionsFeedResponse`        |
| Your playlists      | `AccountPlaylistsResponse`                |
| Playlist contents   | `PlaylistInfosResponse` (browseId `VL…`)  |
| Watch Later         | `PlaylistInfosResponse` (browseId `VLWL`) |
| Liked Videos        | `PlaylistInfosResponse` (browseId `VLLL`) |
| Search              | `SearchResponse`                          |

Auth is just a cookie string captured from `WKWebView`'s shared cookie store
after you sign into youtube.com inside the sign-in sheet. The capture is
filtered to `*.youtube.com`-scoped cookies only — mixing in `.google.com` or
`accounts.google.com` cookies makes InnerTube respond with `loggedOut=true`.
The resulting blob is persisted in the macOS Keychain and handed to
YouTubeKit via `YouTubeModel.cookies`.

The sign-in `WKWebView` spoofs a Safari user-agent, since Google blocks
sign-in from the default `WKWebView` UA. Site data for `youtube.com` /
`google.com` is also cleared before the sheet loads, so stale visitor
cookies from prior attempts don't trip Google's embedded-browser detection.

## Troubleshooting

- **Sheet doesn't auto-close after you sign in** — you haven't fully landed
  on `youtube.com` yet. Cookie-consent and "choose account" interstitials
  count; finish those until the status bar URL shows `www.youtube.com`,
  then click **Done**.
- **Google shows "This browser or app may not be secure"** — stale visitor
  cookies are tripping Google's detection. Sign out from Settings (which
  wipes the WKWebView store), reopen the sign-in sheet, try again.
- **Subscriptions / playlists empty after signing in** — enable verbose
  logging to see what the capture produced:
  `log stream --predicate 'subsystem == "app.youmenutube"' --level debug`.
  If session markers (SAPISID, SID, LOGIN_INFO, __Secure-3PSIDTS) are all
  present but InnerTube still says `loggedOut=true`, YouTubeKit may be out
  of date — check for a newer release.
- **Embed player won't play** — some videos forbid embedding. Open the video
  on youtube.com instead by editing `YouTubeEmbedView.load` in
  `Sources/Views/PlayerWindow.swift`.
