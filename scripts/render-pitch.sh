#!/bin/bash
#
# Renders scripts/pitch-image.html into assets/pitch.jpg and assets/pitch-light.jpg.
#
# 1200x630 at a 2x scale factor, so the output is 2400x1260 — 1.91:1, which is
# the shape link previews crop to, and sharp enough to sit full width on the
# site. Two files because the page and the README both follow the reader's
# light or dark preference, and one dark banner on a white page looks like a
# hole in it.
#
#   ./scripts/render-pitch.sh
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/scripts/pitch-image.html"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$chrome" ]; then
  echo "render-pitch: no Chrome at $chrome — set CHROME=/path/to/chrome" >&2
  exit 1
fi

shoot() {  # shoot <theme> <out.jpg>
  local theme="$1" out="$2" q
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=1200,630 \
    --default-background-color=00000000 \
    --screenshot="$tmp/$theme.png" "file://$src?theme=$theme" >/dev/null 2>&1

  [ -s "$tmp/$theme.png" ] || { echo "render-pitch: $theme render produced nothing" >&2; exit 1; }

  # JPEG rather than PNG: this is a full-bleed banner with a gradient behind it,
  # where PNG is several times the size for no visible gain.
  sips -s format jpeg -s formatOptions 82 "$tmp/$theme.png" --out "$out" >/dev/null
  echo "  $(basename "$out")  $(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/{printf "%s ", $2}')  $(du -h "$out" | cut -f1)"
}

echo "render-pitch:"
shoot dark  "$root/assets/pitch.jpg"
shoot light "$root/assets/pitch-light.jpg"
