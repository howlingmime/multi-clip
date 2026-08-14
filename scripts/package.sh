#!/bin/bash
# Build MultiClip and wrap it in a .app bundle.
#
# The bundle matters for more than tidiness: Accessibility (TCC) permission is
# granted to a code identity, not a file path. A bare `swift build` binary run
# from a terminal borrows the terminal's permission, and an ad-hoc signature
# changes hash on every rebuild — so the grant is lost each time. Signing the
# bundle with a stable identity means you grant Accessibility once.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MultiClip"
BUNDLE_ID="${MULTICLIP_BUNDLE_ID:-dev.howlingmime.MultiClip}"
DEST="${1:-$HOME/Applications}"
APP="$DEST/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

VERSION="$(git describe --tags --always 2>/dev/null || echo 0.1.0)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

# Prefer a real Developer ID / Apple Development identity so the signature is
# stable across rebuilds; fall back to ad-hoc if none is installed. Override
# with CODESIGN_IDENTITY if you have several and want a specific one.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"

if [ -n "$IDENTITY" ]; then
    echo "==> Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" \
        --options runtime --timestamp=none "$APP"
else
    echo "==> No signing identity found; signing ad-hoc"
    echo "    (Accessibility permission will reset on every rebuild)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

codesign --verify --verbose=1 "$APP"
echo "==> Done: $APP"
