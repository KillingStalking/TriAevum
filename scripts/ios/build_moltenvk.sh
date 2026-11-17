#!/usr/bin/env bash
# Build the official static iOS MoltenVK XCFramework on a macOS/Xcode host.
# Copyright TriAevum contributors
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_ROOT="${TRIAEVUM_IOS_DEPS_DIR:-$ROOT/build/ios-deps}"
MOLTENVK_REF="${MOLTENVK_REF:-5189f8de86ec365860f63bf1da736815cfaea5cd}"
MOLTENVK_SOURCE_DIR="${MOLTENVK_SOURCE_DIR:-$BUILD_ROOT/MoltenVK}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "MoltenVK iOS packaging requires macOS and Xcode; use a macOS GitHub Actions runner." >&2
    exit 2
fi
if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    echo "Xcode command-line tools and make are required." >&2
    exit 2
fi

mkdir -p "$BUILD_ROOT"
if [[ ! -d "$MOLTENVK_SOURCE_DIR/.git" ]]; then
    git clone https://github.com/KhronosGroup/MoltenVK.git "$MOLTENVK_SOURCE_DIR"
fi
git -C "$MOLTENVK_SOURCE_DIR" fetch --depth=1 origin "$MOLTENVK_REF"
git -C "$MOLTENVK_SOURCE_DIR" checkout --detach FETCH_HEAD

ACTUAL_REF="$(git -C "$MOLTENVK_SOURCE_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_REF" != "$MOLTENVK_REF" ]]; then
    echo "MoltenVK checkout mismatch: expected $MOLTENVK_REF, got $ACTUAL_REF" >&2
    exit 3
fi

(
    cd "$MOLTENVK_SOURCE_DIR"
    ./fetchDependencies --ios --keep-cache
    make ios
)

XCFRAMEWORK="$MOLTENVK_SOURCE_DIR/Package/Latest/MoltenVK/static/MoltenVK.xcframework"
if [[ ! -f "$XCFRAMEWORK/Info.plist" ]]; then
    echo "Expected static iOS MoltenVK XCFramework was not produced: $XCFRAMEWORK" >&2
    find "$MOLTENVK_SOURCE_DIR/Package" -maxdepth 7 -name '*.xcframework' -print >&2 || true
    exit 4
fi

echo "THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK=$XCFRAMEWORK"
