#!/bin/bash
#
# Builds dist/KeepAwake.app. That is all this script does: signing, disk
# image creation and notarization happen in .github/workflows/release.yml.
#
# Settings (environment variables, all optional):
#   BUNDLE_ID     Bundle identifier.  Default: com.example.KeepAwake
#   UNIVERSAL=1   Build for Apple silicon + Intel (needs full Xcode).
#
# Example:
#   BUNDLE_ID=com.yourname.KeepAwake ./build.sh

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="KeepAwake"
BUNDLE_ID="${BUNDLE_ID:-com.rebecca.KeepAwake}"
UNIVERSAL="${UNIVERSAL:-1}"

DIST="dist"
APP="$DIST/$APP_NAME.app"

step() { printf '\n==> %s\n' "$1"; }

step "Building (release)"
ARCH_FLAGS=""
if [ "$UNIVERSAL" = "1" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

step "Assembling $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"

echo
echo "Built $APP (not signed)."
