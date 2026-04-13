#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# YouMenuTube — one-shot bootstrap
#
# Usage:
#   ./bootstrap.sh              # install prereqs, generate project, open Xcode
#   ./bootstrap.sh --no-open    # generate only, don't open Xcode
#   ./bootstrap.sh --clean      # also blow away DerivedData & the xcodeproj
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

trap 'echo >&2; printf "\033[1;31m✗ bootstrap.sh failed at line %s (command: %s)\033[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

open_xcode=1
clean=0
for arg in "$@"; do
    case "$arg" in
        --no-open) open_xcode=0 ;;
        --clean)   clean=1 ;;
        -h|--help)
            sed -n '2,9p' "$0"; exit 0 ;;
        *)
            echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
red()   { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }
step() { bold "▸ $*"; }

# ── 1. Sanity: macOS + Xcode ─────────────────────────────────────────────────
step "Checking environment"
if [[ "$(uname)" != "Darwin" ]]; then
    red "This project builds on macOS only."; exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    red "Xcode command-line tools not found. Install Xcode from the App Store, then run: xcode-select --install"
    exit 1
fi
xcodebuild_out=$(xcodebuild -version 2>/dev/null || true)
xcode_ver=$(awk 'NR==1 { print $2 }' <<<"$xcodebuild_out")
xcode_ver=${xcode_ver:-0}
xcode_major=${xcode_ver%%.*}
if ! [[ "$xcode_major" =~ ^[0-9]+$ ]] || (( xcode_major < 16 )); then
    yellow "  Xcode $xcode_ver detected — this project targets macOS 15 and expects Xcode 16+."
fi
green "  ✓ macOS + Xcode $xcode_ver"

# ── 2. Homebrew + XcodeGen ───────────────────────────────────────────────────
step "Ensuring XcodeGen is installed"
if ! command -v xcodegen >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        red "Homebrew is required to install XcodeGen. Install it from https://brew.sh and re-run."
        exit 1
    fi
    bold "  Installing xcodegen via Homebrew…"
    brew install xcodegen
fi
green "  ✓ xcodegen $(xcodegen --version 2>/dev/null | head -n1)"

# ── 3. Optional cleanup ──────────────────────────────────────────────────────
if [[ "$clean" -eq 1 ]]; then
    step "Cleaning generated artifacts"
    rm -rf YouMenuTube.xcodeproj build DerivedData
    green "  ✓ Removed xcodeproj, build/, DerivedData/"
fi

# ── 4. Generate project ──────────────────────────────────────────────────────
step "Generating Xcode project"
xcodegen generate --quiet
green "  ✓ YouMenuTube.xcodeproj generated"

# ── 5. Resolve SPM dependencies ──────────────────────────────────────────────
step "Resolving Swift Package dependencies"
xcodebuild -resolvePackageDependencies \
    -project YouMenuTube.xcodeproj \
    -scheme YouMenuTube \
    >/dev/null 2>&1 || yellow "  (package resolution will retry on first Xcode build)"

# ── 5b. Pre-commit hook ──────────────────────────────────────────────────────
if [[ -d .git ]]; then
    step "Wiring git hooks"
    git config core.hooksPath .githooks
    green "  ✓ core.hooksPath = .githooks (runs swift-format on staged files)"
fi

# ── 6. Open ──────────────────────────────────────────────────────────────────
if [[ "$open_xcode" -eq 1 ]]; then
    step "Opening in Xcode"
    open YouMenuTube.xcodeproj
fi

echo
green "Done. Press ⌘R in Xcode to build and run."
green "On first launch, click 'Sign in' and log into youtube.com inside the sheet."
