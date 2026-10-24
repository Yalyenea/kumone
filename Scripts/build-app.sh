#!/bin/bash
# Builds Kumone with SwiftPM and wraps the product into a .app bundle.
# Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

CONF="${1:-debug}"
APP_NAME="Kumone"
BUNDLE_ID="im.missuo.Kumone"
# Version resolution: environment > version.env > defaults.
ENV_MARKETING_VERSION="${MARKETING_VERSION:-}"
ENV_BUILD_NUMBER="${BUILD_NUMBER:-}"
MARKETING_VERSION="0.1.0"
BUILD_NUMBER="1"
[ -f "$ROOT/version.env" ] && source "$ROOT/version.env"
[ -n "$ENV_MARKETING_VERSION" ] && MARKETING_VERSION="$ENV_MARKETING_VERSION"
[ -n "$ENV_BUILD_NUMBER" ] && BUILD_NUMBER="$ENV_BUILD_NUMBER"

BUILD_DIR="$ROOT/.build/app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# ARCHES="arm64 x86_64" builds a universal binary; default is the host architecture.
# Build each architecture separately and join the slices with lipo.

# Extra SwiftPM flags supplied explicitly by the caller.
EXTRA_FLAGS=()
for flag in ${SWIFT_BUILD_FLAGS:-}; do
  EXTRA_FLAGS+=("$flag")
done

# Record the real SDK version in the linked binary. Left to itself, SwiftPM
# passes the deployment target as both the minimum *and* the SDK version on
# the linker's `-platform_version` flag, so the app reads as one built with
# the macOS 15 SDK — and the system then gives it the legacy window
# appearance on macOS 26/27 (no current-generation chrome) even though it was
# built on a machine running the new SDK.
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VERSION" ]; then
  EXTRA_FLAGS+=(-Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION")
fi

# ${arr[@]+...} keeps macOS's bash 3.2 happy under set -u with empty arrays
build_slice() { # [triple] — prints nothing; sets SLICE_BIN_PATH
  local triple_flags=()
  [ -n "${1:-}" ] && triple_flags=(--triple "$1")
  swift build -c "$CONF" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    ${triple_flags[@]+"${triple_flags[@]}"} --product "$APP_NAME"
  SLICE_BIN_PATH="$(swift build -c "$CONF" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    ${triple_flags[@]+"${triple_flags[@]}"} --show-bin-path)"
}

SLICE_BINARIES=()
if [ -n "${ARCHES:-}" ]; then
  for arch in $ARCHES; do
    build_slice "$arch-apple-macosx"
    SLICE_BINARIES+=("$SLICE_BIN_PATH/$APP_NAME")
    # Resources and the metallib search below use the first slice's tree;
    # every slice carries the same resources.
    BIN_PATH="${BIN_PATH:-$SLICE_BIN_PATH}"
  done
else
  build_slice ""
  BIN_PATH="$SLICE_BIN_PATH"
  SLICE_BINARIES+=("$BIN_PATH/$APP_NAME")
fi

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

if [ "${#SLICE_BINARIES[@]}" -gt 1 ]; then
  lipo -create "${SLICE_BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
  cp "${SLICE_BINARIES[0]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Localization tables → Bundle.main
cp "$ROOT/Sources/Kumone/Resources/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"
for lproj in "$ROOT"/Sources/Kumone/Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done

# Copy SwiftPM resource bundles, excluding test resources.
find "$BIN_PATH" -maxdepth 1 -name '*.bundle' -not -name '*Tests*' \
  -print0 |
  while IFS= read -r -d '' bundle; do
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
  done

# App icon: compile the Icon Composer bundle into Assets.car and keep the
# source bundle alongside for Liquid Glass light/dark rendering on macOS 26.
ICON_SOURCE="$ROOT/AppIcon.icon"
if [ -d "$ICON_SOURCE" ]; then
  cp -R "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icon"
  xcrun actool "$ICON_SOURCE" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --notices --warnings --errors \
    --output-partial-info-plist "$BUILD_DIR/icon-partial.plist" \
    --app-icon AppIcon \
    --enable-on-demand-resources NO \
    --development-region zh-Hans \
    --target-device mac \
    --minimum-deployment-target 15.0 \
    --platform macosx >/dev/null
  if [ ! -f "$APP_BUNDLE/Contents/Resources/Assets.car" ]; then
    echo "ERROR: actool did not produce Assets.car" >&2
    exit 1
  fi
fi

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconName</key><string>AppIcon</string>
        </dict>
    </dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 missuo</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
    <key>KumoneGitCommit</key><string>$GIT_COMMIT</string>
</dict>
</plist>
PLIST

if [ -n "${ARCHES:-}" ]; then
  echo "Binary architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
fi

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Built $APP_BUNDLE ($CONF, $GIT_COMMIT)"
