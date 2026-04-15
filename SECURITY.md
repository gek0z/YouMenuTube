# Security Policy

YouMenuTube is a personal-use macOS menu-bar app that authenticates against
YouTube by importing a session cookie blob from the user's own browser
(Safari / Chrome / Firefox / Edge / Arc / Brave / Vivaldi / Opera / Helium)
and storing it on-device. This document describes how to report
vulnerabilities, what's in scope, and how the app handles credentials.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Use one of the following private channels:

- GitHub's [private vulnerability reporting](https://github.com/gek0z/YouMenuTube/security/advisories/new)
  (preferred: gives us a private discussion thread + draft advisory).
- Email the maintainer (see the GitHub profile of [@gek0z](https://github.com/gek0z)).

Please include:

1. A clear description of the issue and its impact.
2. Steps to reproduce, ideally with a minimal repro and the YouMenuTube
   version (`Settings → About → Version` or `git rev-parse --short HEAD`).
3. Your macOS / Xcode versions if relevant.
4. Whether you'd like to be credited in the advisory.

We aim to acknowledge reports within 7 days. Because this is a hobby project,
fix turnaround depends on availability; critical issues will be prioritised.

## Supported versions

Only `main` is supported. Older tagged releases will not receive backported
fixes; upgrade to the latest release.

## Scope

In scope:

- Code and configuration in this repository.
- The release `.dmg` artefacts published from this repository.
- The pre-commit hook and CI workflows.

Out of scope:

- Vulnerabilities in YouTube, Google, or any first-party Apple framework.
- Vulnerabilities in third-party dependencies (report those upstream; currently
  only [YouTubeKit](https://github.com/b5i/YouTubeKit)).
- The fact that YouMenuTube uses YouTube's internal **InnerTube** API. This is
  documented in the README and is a deliberate design choice, not a security
  bug.
- Issues that require an attacker who already has root / your unlocked Mac.

## What the app stores, and where

- **Session cookies** imported from the user's browser (filtered to
  `*.youtube.com` only) are written to the macOS Keychain under service
  `com.youmenutube.app`, account `youtube.cookies.v1`. This is the only
  credential material the app persists. **Sign Out** wipes it.
- **`@AppStorage` preferences** (autoplay, hide-Shorts, pinned playlist,
  player-floats-on-top) live in standard `NSUserDefaults`.

## What the app reads from other apps (and when it asks)

The "Import YouTube session" flow reads `youtube.com` cookies directly out
of the selected browser's on-disk cookie store:

- **Safari** requires the user to grant YouMenuTube **Full Disk Access**
  (System Settings → Privacy & Security → Full Disk Access) because the
  Safari cookie file lives inside a protected container. Without this grant
  the reader fails cleanly; it cannot silently read Safari cookies.
- **Chromium-family browsers** (Chrome, Edge, Arc, Brave, Vivaldi, Opera,
  Helium) encrypt their cookie values with an AES key stored in the macOS
  login Keychain under e.g. `Chrome Safe Storage` (or `Helium Storage Key`
  for Helium). The app calls `SecItemCopyMatching`, which triggers the
  standard macOS keychain-access prompt ("Always Allow" / "Allow" / "Deny").
  We only read the Safe Storage key and only for the selected browser.
- **Firefox** stores cookie values in plain text; no Keychain access is
  needed.

In every case we select only rows whose host matches `youtube.com`, discard
everything else before it leaves the reader, and validate that at least one
session marker (`SAPISID`, `__Secure-3PAPISID`, `SID`, `LOGIN_INFO`, …) is
present. No other domain's cookies are ever persisted or sent.

## What the app does *not* do

- No telemetry, analytics, crash reporting, or remote configuration.
- No outbound network traffic except to `youtube.com` and YouTube's
  InnerTube endpoints.
- No background activity when the menu bar popover is closed.

If you find evidence to the contrary, that's a bug; please report it.
