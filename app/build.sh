#!/bin/bash
#
# Builds "Tideline.app" into ./dist.
#
#   ./build.sh                 universal release build, ad-hoc signed
#   ./build.sh --install       also copy it into /Applications and launch it
#   ./build.sh --zip           also produce a zip next to the app
#   ./build.sh --notarize      sign, notarize with Apple, staple, and zip
#
# The version is read from ../package.json. Bump it with `npm version patch`
# (or minor/major), which rebuilds the app so the bundle matches the tag.
#
# To sign with a Developer ID for distribution:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh --zip
#
# In CI, pass credentials as NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD.
#
# Locally, to ship it to other Macs it also has to be notarized. Store once:
#   xcrun notarytool store-credentials tideline \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# then:
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./build.sh --notarize

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Tideline"
EXECUTABLE="Tideline"
# The version lives in package.json; VERSION= overrides it for one-off builds.
if [ -z "${VERSION:-}" ]; then
  if command -v node >/dev/null 2>&1; then
    VERSION="$(node -p "require('../package.json').version" 2>/dev/null || true)"
  fi
  if [ -z "${VERSION:-}" ]; then
    VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ../package.json 2>/dev/null | head -1)"
  fi
fi
if [ -z "${VERSION:-}" ]; then
  echo "Could not determine the version from ../package.json (set VERSION= to override)." >&2
  exit 1
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tideline}"
# CI has no stored profile, so credentials can come from the environment instead.
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"

DIST="dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

INSTALL=0
ZIP=0
NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --zip) ZIP=1 ;;
    --notarize) NOTARIZE=1; ZIP=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Notarization needs a real Developer ID; Apple rejects ad-hoc signatures.
if [ "$NOTARIZE" -eq 1 ] && [ "$IDENTITY" = "-" ]; then
  echo "--notarize needs a Developer ID. Set CODESIGN_IDENTITY, e.g." >&2
  echo "  CODESIGN_IDENTITY=\"\$(security find-identity -v -p codesigning \\" >&2
  echo "    | sed -n 's/.*\"\(Developer ID Application: [^\"]*\)\".*/\1/p' | head -1)\"" >&2
  exit 1
fi

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build -c release --arch arm64 --arch x86_64
BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling the bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
chmod +x "$CONTENTS/MacOS/$EXECUTABLE"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
  Resources/Info.plist > "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Drawing the icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
swift Tools/make-icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing with identity: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  # No --deep: Apple discourages it, and this bundle has no nested code.
  # --options runtime (hardened runtime) is required for notarization.
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

if [ "$ZIP" -eq 1 ]; then
  echo "==> Zipping"
  rm -f "$DIST/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"
fi

if [ "$NOTARIZE" -eq 1 ]; then
  echo "==> Submitting to Apple for notarization (this takes a few minutes)"
  if [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_TEAM_ID" ] && [ -n "$NOTARY_PASSWORD" ]; then
    xcrun notarytool submit "$DIST/$APP_NAME.zip" \
      --apple-id "$NOTARY_APPLE_ID" \
      --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" \
      --wait
  else
    xcrun notarytool submit "$DIST/$APP_NAME.zip" \
      --keychain-profile "$NOTARY_PROFILE" --wait
  fi

  # The ticket is stapled to the .app, not the zip, so the zip is rebuilt after.
  echo "==> Stapling the ticket"
  xcrun stapler staple "$APP"

  echo "==> Re-zipping the stapled app"
  rm -f "$DIST/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"

  echo "==> Verifying Gatekeeper acceptance"
  spctl --assess --type execute --verbose=2 "$APP"
fi

if [ "$INSTALL" -eq 1 ]; then
  echo "==> Installing to /Applications"
  osascript -e 'quit app "Tideline"' 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
fi

echo
echo "Done: $(pwd)/$APP"
[ "$ZIP" -eq 1 ] && echo "Zip:  $(pwd)/$DIST/$APP_NAME.zip"
exit 0
