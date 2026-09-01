#!/bin/bash
#
# Renders scripts/social-image.html into assets/social-1.12.jpg and
# assets/social-1.12-light.jpg.
#
# 1200x630 at a 2x scale factor, so the output is 2400x1260 — the same 1.91:1
# the pitch banner uses, which is what X and LinkedIn crop a link preview to.
# Two themes for the same reason the pitch banner has two: whichever one gets
# posted, it should not be the one that looks like a hole in the timeline.
#
#   ./scripts/render-social.sh
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/scripts/social-image.html"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$chrome" ]; then
  echo "render-social: no Chrome at $chrome — set CHROME=/path/to/chrome" >&2
  exit 1
fi

shoot() {  # shoot <theme> <out.jpg>
  local theme="$1" out="$2"
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=1200,630 \
    --default-background-color=00000000 \
    --screenshot="$tmp/$theme.png" "file://$src?theme=$theme" >/dev/null 2>&1

  [ -s "$tmp/$theme.png" ] || { echo "render-social: $theme render produced nothing" >&2; exit 1; }

  sips -s format jpeg -s formatOptions 86 "$tmp/$theme.png" --out "$out" >/dev/null
  echo "  $(basename "$out")  $(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/{printf "%s ", $2}')  $(du -h "$out" | cut -f1)"
}

echo "render-social:"
shoot dark  "$root/assets/social-1.12.jpg"
shoot light "$root/assets/social-1.12-light.jpg"
