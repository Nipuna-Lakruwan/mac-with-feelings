#!/usr/bin/env bash
# Builds "build/Mac With Feelings.app" (Apple silicon + Intel) and an ad-hoc signed zip.
#   scripts/build-app.sh            # release build
#   scripts/build-app.sh --install  # also copy it to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Mac With Feelings.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

echo "==> Building $VERSION"
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacWithFeelings

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacWithFeelings"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Drawing the icon"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
"$BIN" --render-icon "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  [ $size -lt 512 ] && sips -z $double $double "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"

(cd build && rm -f MacWithFeelings.zip && ditto -c -k --keepParent "Mac With Feelings.app" MacWithFeelings.zip)
echo "==> Built $APP and build/MacWithFeelings.zip"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MacWithFeelings 2>/dev/null || true
  rm -rf "/Applications/Mac With Feelings.app"
  cp -R "$APP" /Applications/
  echo "==> Installed to /Applications"
fi
