#!/bin/bash
#
# Assembles the publishable site into a directory, which the Pages workflow
# uploads and `npm run site` serves. There is no build step: the pages are
# hand-written HTML and this only copies files into place.
#
# It exists because the screenshots are versioned. They live in assets/<version>/
# so the README can pin a release, but a page that named a version would have to
# be edited on every new set — fourteen files, by hand, to change a number. So
# the pages ask for assets/shots/ and the newest versioned folder is staged as
# that.
#
#   ./site/stage.sh _site
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-_site}"
[[ "$out" = /* ]] || out="$PWD/$out"

rm -rf "$out"
mkdir -p "$out"
cp -R "$root/site/." "$out/"

# The staging script is not part of what gets served.
rm -f "$out/stage.sh"

# [0-9]* rather than * so only the release-numbered folders count, and sort -V
# so 1.10.0 lands after 1.9.0 the way a plain sort would not.
shots="$(find "$root/assets" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' | sort -V | tail -1)"
if [ -z "$shots" ]; then
  echo "stage: no assets/<version>/ folder — the pages have no screenshots to show." >&2
  exit 1
fi

mkdir -p "$out/assets"
cp "$root/assets/pitch.jpg" "$out/assets/pitch.jpg"
cp "$root/assets/pitch-light.jpg" "$out/assets/pitch-light.jpg"
cp "$root/assets/tour.mp4" "$out/assets/tour.mp4"
cp "$root/assets/tour-poster.jpg" "$out/assets/tour-poster.jpg"
cp -R "$shots" "$out/assets/shots"

# Every image and stylesheet the pages ask for has to be there. Without this a
# deploy happily ships a page full of broken frames and nothing says so until
# somebody looks at it.
missing=0
while IFS= read -r ref; do
  [ -e "$out/$ref" ] || { echo "stage: missing $ref" >&2; missing=1; }
done < <(grep -rho 'assets/[A-Za-z0-9._/-]*' "$out" --include='*.html' | sort -u)
[ "$missing" -eq 0 ] || { echo "stage: referenced assets are missing." >&2; exit 1; }

echo "stage: $out — screenshots from ${shots#"$root"/}"
