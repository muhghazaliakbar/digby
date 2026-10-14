#!/bin/bash
# Builds a universal Release of Digby and packages it as a DMG and a ZIP in ./dist.
#
#   scripts/release.sh            ad-hoc signed (runs everywhere after a one-time Gatekeeper approval)
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… scripts/release.sh
#                                 Developer ID signed and notarized (no Gatekeeper prompt)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Digby.xcodeproj/project.pbxproj | head -1)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/Digby.app"
NAME="Digby-$VERSION"

echo "==> Building Digby $VERSION (universal)"
rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"
xcodebuild -project Digby.xcodeproj -scheme Digby -configuration Release \
  -derivedDataPath "$BUILD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
  build | grep -E "error:|warning:|BUILD" || true
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

echo "==> Signing ($SIGN_IDENTITY)"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Digby"

echo "==> Packaging"
STAGE="$BUILD/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Digby $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"

if [[ -n "${NOTARY_PROFILE:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$DIST/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DIST/$NAME.dmg"
fi

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "==> Done"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
