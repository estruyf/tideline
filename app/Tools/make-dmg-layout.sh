#!/bin/bash
#
# Records the disk image's window layout into app/Resources/dmg/DS_Store, which
# is committed and copied into every DMG build.
#
#   ./Tools/make-dmg-layout.sh
#
# Run it by hand on a Mac with a logged-in Finder, once, and again whenever the
# background art or the icon positions change. It is deliberately not part of
# build.sh: laying a window out means driving Finder over AppleScript, and a CI
# runner has no Finder session to drive. Doing it here and committing the result
# is what makes the release build deterministic.
#
# The volume is always named "Tideline", with no version in it. Finder stores
# the background as a reference relative to the volume, so a volume named
# something else on the next release would open with a blank window.
#
# Two things about this script are not obvious and were both learned the hard
# way, by building an image, opening it, and measuring the screenshot:
#
#   * The view options have to be set inside a `tell its icon view options`
#     block. Assigning through a variable — `set opts to the icon view options
#     of w` and then `set icon size of opts` — is accepted without error and
#     silently does nothing, so the image comes out with 64px icons and no
#     background. Finder also has to be frontmost.
#
#   * Finder must not be showing hidden files while it lays this out. With
#     `AppleShowAllFiles` on, the `.background` folder is a visible item, Finder
#     auto-places it, and the two icons that were positioned by hand come out
#     about 48 points below where they were put — consistently enough across
#     rebuilds to look like a rule worth compensating for. It is not one. The
#     script turns the setting off for the duration and puts it back, so the
#     layout does not depend on how whoever runs it likes their Finder. That
#     costs two Finder restarts, which close any windows that are open.
#
set -euo pipefail

cd "$(dirname "$0")/.."

VOLUME="Tideline"
MOUNT="/Volumes/$VOLUME"
BACKGROUND="../assets/dmg/background.tiff"
# Stored without the leading dot on purpose: .gitignore's first line is
# .DS_Store, so the recorded layout would never be committed under its real
# name. build.sh renames it back on the way into the image.
TARGET="Resources/dmg/DS_Store"
APP="dist/Tideline.app"

# The window, and where the two icons sit in it. These numbers are the contract
# with scripts/dmg-background.html — the picture draws a well around each icon,
# so moving one here means re-rendering the background to match.
WIDTH=640
# Taller than the artwork by the height of a title bar, because Finder takes
# that out of the bounds it is given: 453 asks for a window whose *content* is
# the 420 the picture is drawn at. Get this wrong in one direction and the
# bottom of the picture is cropped; wrong in the other and the view is
# scrollable, which shows up as a scroll bar down the right edge.
HEIGHT=453
ICON_Y=198          # the icon's centre; the artwork draws a well around it
APP_X=160
APPS_X=480

[ -d "$APP" ] || { echo "make-dmg-layout: no $APP — run ./build.sh first" >&2; exit 1; }
[ -f "$BACKGROUND" ] || { echo "make-dmg-layout: no $BACKGROUND — run ../scripts/render-dmg-background.sh" >&2; exit 1; }

tmp="$(mktemp -d)"
device=""
# Empty means the key was never set, which is not the same as set to false:
# putting back a literal false would leave the machine subtly changed.
SHOW_ALL_WAS="$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || true)"
cleanup() {
  [ -n "$device" ] && hdiutil detach "$device" -quiet -force 2>/dev/null || true
  rm -rf "$tmp"
  # `defaults read` answers 1 or 0, and `defaults write -bool` refuses both:
  # it takes true/false. Handing the value straight back prints the usage
  # screen and silently leaves the setting where this script put it.
  case "$SHOW_ALL_WAS" in
    "")            defaults delete com.apple.finder AppleShowAllFiles 2>/dev/null || true ;;
    1|YES|yes|true|TRUE) defaults write com.apple.finder AppleShowAllFiles -bool true ;;
    *)             defaults write com.apple.finder AppleShowAllFiles -bool false ;;
  esac
  killall Finder 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Hiding hidden files while Finder lays this out"
defaults write com.apple.finder AppleShowAllFiles -bool false
killall Finder 2>/dev/null || true
sleep 3

# A read-write image, because Finder has to be able to write its .DS_Store into
# it. The size is generous and irrelevant: this image is thrown away.
echo "==> Creating a scratch image"
hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
hdiutil create -size 300m -fs HFS+ -volname "$VOLUME" -ov -quiet "$tmp/scratch.dmg"
device="$(hdiutil attach "$tmp/scratch.dmg" -nobrowse -noverify -noautoopen \
  | grep '^/dev/' | head -1 | awk '{print $1}')"

echo "==> Filling it the way a release would"
mkdir -p "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.tiff"
cp -R "$APP" "$MOUNT/Tideline.app"
ln -s /Applications "$MOUNT/Applications"
# A leading dot only hides the folder from people who have not asked Finder to
# show hidden files. The flag hides it from everyone.
chflags hidden "$MOUNT/.background"

echo "==> Handing it to Finder"
osascript <<APPLESCRIPT
tell application "Finder"
  activate
  set bgFile to file ".background:background.tiff" of disk "$VOLUME"
  tell disk "$VOLUME"
    open
    delay 1
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set the bounds to {160, 120, $((160 + WIDTH)), $((120 + HEIGHT))}
      tell its icon view options
        set arrangement to not arranged
        set icon size to 128
        set text size to 12
        set label position to bottom
        set shows item info to false
        set background picture to bgFile
      end tell
      delay 1
      set position of item "Tideline.app" to {$APP_X, $ICON_Y}
      set position of item "Applications" to {$APPS_X, $ICON_Y}
    end tell
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Finder writes the .DS_Store when it is good and ready, so the volume is
# flushed and given a moment before the file is taken.
sync
sleep 2

[ -f "$MOUNT/.DS_Store" ] || { echo "make-dmg-layout: Finder wrote no .DS_Store" >&2; exit 1; }
mkdir -p "$(dirname "$TARGET")"
cp "$MOUNT/.DS_Store" "$TARGET"

echo
echo "Wrote $(pwd)/$TARGET ($(du -h "$TARGET" | cut -f1)). Commit it."
echo "Check it by building a DMG and opening it — the live Finder window here"
echo "is not a reliable preview of what the .DS_Store will render."
