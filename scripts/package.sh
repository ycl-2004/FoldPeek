#!/bin/bash
#
# Builds FoldPeek and packages it as a ZIP for hand-to-hand distribution.
#
# This script is run by hand and does nothing else. It does not install,
# does not touch /Applications, does not register anything with the system,
# does not restart Finder, does not download tools, and installs no hook that
# would run it again on its own. Those behaviours were removed from this
# project deliberately; see docs/SECURITY_AUDIT.md.
#
# Usage:  ./scripts/package.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="Build/Release"
APP="$BUILD_DIR/FoldPeek.app"
APPEX="$APP/Contents/PlugIns/FoldPeekPreviewExtension.appex"
DIST="dist"

echo "==> Building Release"
xcodebuild -project FoldPeek.xcodeproj \
           -scheme FoldPeek \
           -configuration Release \
           -derivedDataPath "$ROOT/Build/DerivedData" \
           clean build \
           SYMROOT="$ROOT/Build" \
           OBJROOT="$ROOT/Build/Intermediates.noindex" \
           CODE_SIGN_IDENTITY=- \
           CODE_SIGNING_REQUIRED=YES \
           CODE_SIGNING_ALLOWED=YES \
           ARCHS="arm64 x86_64" \
           ONLY_ACTIVE_ARCH=NO \
           | grep -E '^\*\* (CLEAN|BUILD)|error:'

if [[ ! -d "$APP" ]]; then
  echo "Build produced no app at $APP" >&2
  exit 1
fi

# Ad-hoc signing injects com.apple.security.get-task-allow, which lets any
# process attach a debugger. Re-sign with the entitlements this repo declares
# so a shipped build carries exactly those and nothing else.
echo "==> Re-signing with the repository entitlements"
codesign --force --sign - -o runtime \
  --entitlements FoldPeekPreviewExtension/FoldPeekPreviewExtension.entitlements "$APPEX"
codesign --force --sign - -o runtime \
  --entitlements FoldPeekApp/FoldPeekApp.entitlements "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"

# LaunchServices scans the whole disk, so an app left inside the repository is
# registered alongside the installed one. Two copies of the same extension is
# how the Quick Look panel ends up showing a stale build, or none at all. This
# copy is unregistered as soon as it is built; the ZIP below is the deliverable.
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" \
  -u "$APP" 2>/dev/null || true

host_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
ext_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Contents/Info.plist")
host_archs=$(lipo -archs "$APP/Contents/MacOS/FoldPeek")
ext_archs=$(lipo -archs "$APPEX/Contents/MacOS/FoldPeekPreviewExtension")
host_entitlements=$(codesign -d --entitlements - "$APP" 2>&1 | grep -c '\[Key\]')
ext_entitlements=$(codesign -d --entitlements - "$APPEX" 2>&1 | grep -c '\[Key\]')
echo "    host bundle ID:         $host_bundle_id"
echo "    extension bundle ID:    $ext_bundle_id"
echo "    host architectures:     $host_archs"
echo "    extension architectures: $ext_archs"
echo "    host entitlements:      $host_entitlements (expected 1)"
echo "    extension entitlements: $ext_entitlements (expected 3)"

if [[ "$host_bundle_id" != "com.yichenlin.foldpeek" \
  || "$ext_bundle_id" != "com.yichenlin.foldpeek.preview" ]]; then
  echo "Unexpected bundle identity — refusing to package." >&2
  exit 1
fi

if [[ "$host_archs" != *arm64* || "$host_archs" != *x86_64* \
  || "$ext_archs" != *arm64* || "$ext_archs" != *x86_64* ]]; then
  echo "Universal 2 architecture check failed — refusing to package." >&2
  exit 1
fi

if [[ "$host_entitlements" != "1" || "$ext_entitlements" != "3" ]]; then
  echo "Unexpected entitlement count — refusing to package." >&2
  exit 1
fi

# The extension's third entitlement is a mach-lookup exception, and it must name
# the thumbnail service and nothing else. A count alone would not catch a
# different service being added.
if ! codesign -d --entitlements - "$APPEX" 2>&1 | grep -q 'com.apple.quicklook.ThumbnailsAgent'; then
  echo "Extension is missing the thumbnail-service exception — refusing to package." >&2
  exit 1
fi

if codesign -d --entitlements - "$APP" 2>&1 | grep -q 'get-task-allow' \
  || codesign -d --entitlements - "$APPEX" 2>&1 | grep -q 'get-task-allow'; then
  echo "Debug entitlement survived re-signing — refusing to package." >&2
  exit 1
fi

echo "==> Packaging"
mkdir -p "$DIST"
rm -f "$DIST/FoldPeek.zip" "$DIST/FoldPeek.zip.sha256"
# ditto is the archiver that preserves a bundle's signature; zip does not.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/FoldPeek.zip"
zip_checksum=$(shasum -a 256 "$DIST/FoldPeek.zip" | cut -d' ' -f1)
printf '%s  FoldPeek.zip\n' "$zip_checksum" > "$DIST/FoldPeek.zip.sha256"

echo
echo "Wrote $DIST/FoldPeek.zip ($(du -h "$DIST/FoldPeek.zip" | cut -f1))"
echo "SHA-256: $zip_checksum"
echo
echo "Send the zip together with INSTALL.md — the app is ad-hoc signed, so"
echo "macOS will refuse to open it until the recipient clears the quarantine"
echo "flag. INSTALL.md explains what that means before asking anyone to do it."
