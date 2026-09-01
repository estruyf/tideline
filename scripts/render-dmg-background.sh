#!/bin/bash
#
# Renders scripts/dmg-background.html into assets/dmg/background.tiff — the
# picture behind the two icons in the disk image.
#
# 640x420, which is the size build.sh opens the DMG window to, shot twice: once
# at 1x and once at 2x, then folded into a single TIFF with tiffutil. That is
# what makes it sharp on a Retina display; a lone PNG gets scaled up and the
# text furs at the edges.
#
#   ./scripts/render-dmg-background.sh
#
# The light rendering is written beside it as background-light.tiff. It is not
# what ships — Finder draws the icon labels in the system appearance, and white
# labels on a light background are unreadable — but it is there to swap in if
# the shipped one ever looks wrong.
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/scripts/dmg-background.html"
out="$root/assets/dmg"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

W=640
H=420

chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$chrome" ]; then
  echo "render-dmg-background: no Chrome at $chrome — set CHROME=/path/to/chrome" >&2
  exit 1
fi

mkdir -p "$out"

shoot() {  # shoot <theme> <scale> <out.png>
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$2" --window-size="$W,$H" \
    --screenshot="$3" "file://$src?theme=$1" >/dev/null 2>&1
  [ -s "$3" ] || { echo "render-dmg-background: $1 at ${2}x produced nothing" >&2; exit 1; }
}

build() {  # build <theme> <out.tiff>
  local theme="$1" target="$2"
  shoot "$theme" 1 "$tmp/$theme.png"
  shoot "$theme" 2 "$tmp/$theme@2x.png"

  # tiffutil is fussy about the pair: the second has to be exactly twice the
  # first or the HiDPI check rejects it, which is worth failing on here rather
  # than discovering as a blurry background inside a signed disk image.
  tiffutil -cathidpicheck "$tmp/$theme.png" "$tmp/$theme@2x.png" -out "$target" >/dev/null

  echo "  $(basename "$target")  $(sips -g pixelWidth -g pixelHeight "$target" \
    | awk '/pixel/{printf "%s ", $2}') $(du -h "$target" | cut -f1)"
}

echo "render-dmg-background:"
build dark  "$out/background.tiff"
build light "$out/background-light.tiff"
