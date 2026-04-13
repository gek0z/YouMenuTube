# Security Policy

YouMenuTube is a personal-use macOS menu-bar app that authenticates against
YouTube by capturing a session cookie blob from a `WKWebView` sign-in and
storing it on-device. This document describes how to report vulnerabilities,
what's in scope, and how the app handles credentials.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Use one of the following private channels:

- GitHub's [private vulnerability reporting](https://github.com/gek0z/YouMenuTube/security/advisories/new)
  (preferred — gives us a private discussion thread + draft advisory).
- Email the maintainer (see the GitHub profile of [@gek0z](https://github.com/gek0z)).

Please include:

1. A clear description of the issue and its impact.
2. Steps to reproduce, ideally with a minimal repro and the YouMenuTube
   version (`Settings → About → Version` or `git rev-parse --short HEAD`).
3. Your macOS / Xcode versions if relevant.
4. Whether you'd like to be credited in the advisory.

We aim to acknowledge reports within 7 days. Because this is a hobby project,
fix turnaround depends on availability — critical issues will be prioritised.

## Supported versions

Only `main` is supported. Older tagged releases will not receive backported
fixes — upgrade to the latest release.

## Scope

In scope:

- Code and configuration in this repository.
- The release `.dmg` artefacts published from this repository.
- The pre-commit hook and CI workflows.

Out of scope:

- Vulnerabilities in YouTube, Google, or any first-party Apple framework.
- Vulnerabilities in third-party dependencies (report those upstream — currently
  only [YouTubeKit](https://github.com/b5i/YouTubeKit)).
- The fact that YouMenuTube uses YouTube's internal **InnerTube** API. This is
  documented in the README and is a deliberate design choice, not a security
  bug.
- Issues that require an attacker who already has root / your unlocked Mac.

## What the app stores, and where

- **Session cookies** captured from the sign-in `WKWebView` (filtered to
  `*.youtube.com` only) are written to the macOS Keychain under service
  `com.youmenutube.app`, account `youtube.cookies.v1`. This is the only
  credential material the app persists. **Sign Out** wipes it.
- **WKWebView site data** for `youtube.com` and `google.com` lives in the
  app's standard `WKWebsiteDataStore`. The Sign-In sheet wipes this on open;
  Sign Out wipes it again.
- **`@AppStorage` preferences** (autoplay, hide-Shorts, pinned playlist,
  player-floats-on-top) live in standard `NSUserDefaults`.

## What the app does *not* do

- No telemetry, analytics, crash reporting, or remote configuration.
- No outbound network traffic except to `youtube.com` /
  `accounts.google.com` (sign-in) and YouTube's InnerTube endpoints.
- No background activity when the menu bar popover is closed.

If you find evidence to the contrary, that's a bug — please report it.
