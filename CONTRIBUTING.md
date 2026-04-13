# Contributing to YouMenuTube

Thanks for considering a contribution! YouMenuTube is a small SwiftUI
menu-bar app and the codebase is intentionally compact — read the README
first to get a feel for what the app does and the constraints it operates
under (it's an unofficial client wrapping YouTube's internal **InnerTube**
API; see the disclaimer in the README).

## Quick start

```sh
git clone git@github.com:gek0z/YouMenuTube.git
cd YouMenuTube
./bootstrap.sh          # installs xcodegen if missing, generates the xcodeproj,
                        # resolves SPM packages, and wires the pre-commit hook
```

Then ⌘R in Xcode. Requires **macOS 15 Sequoia** and **Xcode 16+**.

## Project layout

See the "Project layout" section of the [README](README.md). High-level:

- `Sources/App/` — `@main` entry, scenes, root view.
- `Sources/Services/` — `YouTubeService` (the only network surface),
  `PlayerController`, `RefreshTrigger`, `Keychain`.
- `Sources/Views/` — one SwiftUI view per tab, plus the player and sign-in
  windows.
- `Sources/Models/` — `VideoEntry`, `PlaylistEntry`.
- `Tests/` — Swift Testing target.

## Format, lint, test

We use **swift-format** (Apple official) for both formatting and linting.
There is no SwiftLint.

```sh
# Format in place
xcrun swift-format format -i -r --configuration .swift-format Sources Tests

# Lint (CI runs this in --strict mode)
xcrun swift-format lint --strict --recursive --configuration .swift-format Sources Tests

# Tests
xcodebuild -project YouMenuTube.xcodeproj \
  -scheme YouMenuTube \
  -destination 'platform=macOS' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  test
```

The `bootstrap.sh` script wires `core.hooksPath` to `.githooks/`, so a
pre-commit hook automatically runs `swift-format lint --strict` on staged
`.swift` files. If you skip `bootstrap.sh`, install it manually:

```sh
git config core.hooksPath .githooks
```

Configuration lives in [`.swift-format`](.swift-format) (line length 120,
4-space indent).

## CI

GitHub Actions on every PR — but the actual `build-test` job runs **only**
when the PR carries the `run-ci` label, or when triggered manually from the
Actions tab. This keeps macOS minutes from being burned on every push. A
maintainer will usually add the label after a quick eyeball.

## Pull requests

- Keep PRs focused. A bug fix and an unrelated refactor should be two PRs.
- Match the existing style: terse comments, no hypothetical generality, no
  dead code, identifiers should carry meaning instead of comments explaining
  what code does. (See [`CLAUDE.md` in the system prompt of the maintainers'
  AI tooling](.) — same principles apply to humans.)
- Don't add code-level documentation that just narrates the next line. Do
  add a short comment when there's a non-obvious *why* (a workaround, a
  hidden constraint, a quirk of YouTubeKit / Google fingerprinting, etc.).
- Run `swift-format format -i -r ...` before committing — the pre-commit
  hook will reject unformatted files.
- Open an issue first for anything that touches the auth flow, the InnerTube
  cookie filter, or the player window's WKWebView wrapping. Those are
  fragile and have been hand-tuned for specific Google detection / YouTube
  embed errors (see the troubleshooting section of the README and the
  inline comments in `YouTubeService.swift` / `PlayerWindow.swift` /
  `YouTubeSignInSheet.swift`).

## Commit messages

- Imperative mood: "Add Home tab", not "Added" or "Adds".
- Subject ≤ 72 characters; explain *why* in the body, not *what*.
- One topic per commit. We don't squash on merge — keep history readable.

## Reporting bugs

Please use the issue templates under `.github/ISSUE_TEMPLATE/` (coming
soon). For now include:

- macOS version (`sw_vers`)
- Xcode version (`xcodebuild -version`) if building from source
- YouMenuTube version / commit
- Full reproduction steps
- Relevant log output:
  `log stream --predicate 'subsystem == "app.youmenutube"' --level debug`

For **security** issues, see [`SECURITY.md`](SECURITY.md) — please don't
file them publicly.

## License

By contributing, you agree that your contributions will be licensed under
the [Apache License 2.0](LICENSE) (see § 5 of the license for the
contribution clause). Don't include code you can't license under those
terms.
