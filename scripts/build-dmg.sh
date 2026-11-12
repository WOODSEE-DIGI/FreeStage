#!/usr/bin/env bash
#
# build-dmg.sh — build FreeStage (Release) and package it as a DMG that can be
# dragged into /Applications.
#
# Usage:
#   scripts/build-dmg.sh
#   DIST_DIR=/some/other/dir scripts/build-dmg.sh
#   CONFIGURATION=Debug scripts/build-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-dmg.sh
#
# The default identity is "-" (ad-hoc), which is what local, non-notarised
# builds use. FreeStage is distributed outside the Mac App Store and is not
# sandboxed, so the ad-hoc signature plus the exported entitlements is enough
# to run from /Applications on this machine and on other machines after the
# usual Gatekeeper override.
#
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME="FreeStage"
APP_BUNDLE="$APP_NAME.app"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/build}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT_DIR/Resources/FreeStage.entitlements"

log() { printf '==> %s\n' "$*"; }
fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

cd "$ROOT_DIR"

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not found. Install it with: brew install xcodegen"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil not found (macOS command line tools required)"

# The generated project is not committed, so always regenerate it.
log "Generating $APP_NAME.xcodeproj"
xcodegen generate >/dev/null

log "Building $APP_NAME ($CONFIGURATION)"
BUILD_LOG=$(mktemp "${TMPDIR:-/tmp}/freestage-build.XXXXXX")
if ! xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    build >"$BUILD_LOG" 2>&1; then
    printf -- '--- last 40 lines of the build log ---\n' >&2
    tail -n 40 "$BUILD_LOG" >&2
    fail "xcodebuild failed. Full log: $BUILD_LOG"
fi
rm -f "$BUILD_LOG"

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_BUNDLE"
[[ -d "$APP_PATH" ]] || fail "built app not found at $APP_PATH"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist") ||
    fail "could not read CFBundleShortVersionString from $APP_PATH"
DMG_NAME="$APP_NAME-$VERSION.dmg"

# Xcode's incremental product is only linker-signed: the binary has an ad-hoc
# signature but the bundle itself is unsealed. Re-sign the embedded frameworks
# and then the app so codesign seals Contents/Resources and bakes in the
# entitlements (library validation, JIT, networking).
#
# Ad-hoc signatures cannot carry restricted entitlements — AMFI rejects them at
# launch, and Xcode strips them from its own ad-hoc builds. Nothing in this
# bundle ships a system extension (Contents/Library/SystemExtensions is absent),
# so drop them for ad-hoc signing and keep them for a real Developer ID.
SIGN_ENTITLEMENTS="$ENTITLEMENTS"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_ENTITLEMENTS=$(mktemp "${TMPDIR:-/tmp}/freestage-entitlements.XXXXXX")
    cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.system-extension.install' \
        "$SIGN_ENTITLEMENTS" >/dev/null 2>&1 || true
fi

log "Signing with identity '$SIGN_IDENTITY'"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' nested; do
        codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$nested"
    done < <(find "$APP_PATH/Contents/Frameworks" -mindepth 1 -maxdepth 1 -print0)
fi
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    --entitlements "$SIGN_ENTITLEMENTS" \
    "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH" ||
    fail "code signature verification failed for $APP_PATH"

# Stage the drag-to-install layout: the app plus a symlink to /Applications.
STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/freestage-dmg.XXXXXX")
cleanup() {
    rm -rf "$STAGE_DIR"
    [[ "$SIGN_ENTITLEMENTS" == "$ENTITLEMENTS" ]] || rm -f "$SIGN_ENTITLEMENTS"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE_DIR/$APP_BUNDLE"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

log "Creating $DMG_PATH"
hdiutil create -quiet \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null
hdiutil verify -quiet "$DMG_PATH" || fail "DMG verification failed for $DMG_PATH"

SIZE=$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')
SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

printf '\n'
log "Built $DMG_PATH ($SIZE)"
printf '    version  : %s\n' "$VERSION"
printf '    sha256   : %s\n' "$SHA"
printf '\n'
printf 'Install: open the DMG, drag %s into Applications.\n' "$APP_NAME"
printf 'If Gatekeeper blocks the first launch (unsigned/not notarised):\n'
printf '    xattr -dr com.apple.quarantine /Applications/%s\n' "$APP_BUNDLE"
printf 'or right-click the app and choose Open.\n'
