#!/usr/bin/env bash
#
# Copies the two build inputs into public/. Both are ignored by git — the
# recording because it is 7 MB and belongs to whoever recorded it, the icon
# because it is drawn by the app's own generator and would only ever go stale
# sitting here.
#
#   ./scripts/assets.sh                          # the recording at the repo root
#   ./scripts/assets.sh ~/Desktop/other-take.mp4 # a different one

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
recording="${1:-$repo/tideline-demo.mp4}"

if [ ! -f "$recording" ]; then
  echo "no recording at $recording" >&2
  echo "pass one as the first argument, or put tideline-demo.mp4 at the repo root" >&2
  exit 1
fi

# The composition addresses the recording by frame number, and those numbers
# only mean anything for the take it was cut against. A different recording
# needs the frame table in src/Promo.tsx rewritten to match.
size="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate \
  -of csv=p=0 "$recording" 2>/dev/null || true)"
if [ "$size" != "1920,1080,30/1" ]; then
  echo "warning: expected 1920x1080 at 30 fps, got ${size:-unknown}" >&2
  echo "         the crops and frame numbers in src/ are cut against that shape" >&2
fi

cp "$recording" "$here/public/demo.mp4"
echo "public/demo.mp4  <- $recording"

# Prefer a locally built bundle over the installed one, so a change to the icon
# generator shows up here before it ships.
for candidate in "$repo/app/dist/Tideline.app" "/Applications/Tideline.app"; do
  icns="$candidate/Contents/Resources/AppIcon.icns"
  if [ -f "$icns" ]; then
    sips -s format png --resampleHeightWidth 1024 1024 "$icns" \
      --out "$here/public/icon.png" >/dev/null
    echo "public/icon.png  <- $icns"
    exit 0
  fi
done

echo "no AppIcon.icns found — build the app first (npm run build at the repo root)" >&2
exit 1
