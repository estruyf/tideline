#!/usr/bin/env bash
#
# tideline-demo-files.sh
#
# Fills a folder with realistic-looking downloads, backdated across several
# days, so you can record Tideline doing its thing on a believable folder.
#
# The files are random bytes with real extensions. Names, sizes and dates look
# right; the files themselves do not open. That is fine for a screen recording
# unless you plan to double-click something.
#
#   ./tideline-demo-files.sh                     # fill ~/Downloads-demo
#   ./tideline-demo-files.sh --reset             # wipe it first, then fill
#   ./tideline-demo-files.sh --folders           # pre-file the old ones into YYYY-MM-DD
#   ./tideline-demo-files.sh --big               # add a 1.4 GB file for the big-file review
#   ./tideline-demo-files.sh --screenshots       # make the .png files real screenshots
#   ./tideline-demo-files.sh --dir ~/Desktop/dl  # somewhere else
#
# Point Tideline at this folder under Filing > Folder. Do not aim it at your
# real ~/Downloads unless you pass --force and you mean it.

set -euo pipefail

DIR="$HOME/Downloads-demo"
MARKER=".tideline-demo"
RESET=0
FOLDERS=0
BIG=0
SHOTS=0
FORCE=0

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'`
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)         DIR="${2:?--dir needs a path}"; shift 2 ;;
    --reset)       RESET=1; shift ;;
    --folders)     FOLDERS=1; shift ;;
    --big)         BIG=1; shift ;;
    --screenshots) SHOTS=1; shift ;;
    --force)       FORCE=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

DIR="${DIR/#\~/$HOME}"

case "$DIR" in
  "$HOME"|"$HOME/"|"/"|"") echo "refusing to use $DIR" >&2; exit 1 ;;
esac

if [ "$DIR" = "$HOME/Downloads" ] && [ "$FORCE" -eq 0 ]; then
  echo "That is your real Downloads folder. Pass --force if you really want it." >&2
  exit 1
fi

if [ "$RESET" -eq 1 ] && [ -d "$DIR" ]; then
  if [ ! -f "$DIR/$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo "$DIR was not made by this script (no $MARKER). Not wiping it." >&2
    exit 1
  fi
  rm -rf "${DIR:?}"/* "${DIR:?}"/.tideline-demo
fi

mkdir -p "$DIR"
: > "$DIR/$MARKER"

HAVE_SETFILE=0
command -v SetFile >/dev/null 2>&1 && HAVE_SETFILE=1

# ---------------------------------------------------------------- date helpers

rand_hour() { echo $(( RANDOM % 12 + 8 )); }
rand_min()  { echo $(( RANDOM % 60 )); }

day_folder() { date -v-"$1"d +"%Y-%m-%d"; }

set_dates() {
  local path="$1" days="$2"
  local h m
  h=$(rand_hour); m=$(rand_min)
  touch -t "$(date -v-"${days}"d -v"${h}"H -v"${m}"M -v0S +"%Y%m%d%H%M.%S")" "$path"
  if [ "$HAVE_SETFILE" -eq 1 ]; then
    SetFile -d "$(date -v-"${days}"d -v"${h}"H -v"${m}"M -v0S +"%m/%d/%Y %H:%M:%S")" "$path"
  fi
}

# ---------------------------------------------------------------- file helpers

# make_file <days ago> <name> <size in KB>
make_file() {
  local days="$1" name="$2" kb="$3"
  local dest="$DIR"

  if [ "$FOLDERS" -eq 1 ] && [ "$days" -gt 0 ]; then
    dest="$DIR/$(day_folder "$days")"
    mkdir -p "$dest"
  fi

  local path="$dest/$name"

  case "$name" in
    *.png)
      if [ "$SHOTS" -eq 1 ]; then
        screencapture -x -t png "$path" 2>/dev/null || dd if=/dev/urandom of="$path" bs=1024 count="$kb" 2>/dev/null
      else
        dd if=/dev/urandom of="$path" bs=1024 count="$kb" 2>/dev/null
      fi
      ;;
    *)
      if [ "$kb" -ge 51200 ]; then
        # sparse, so a 1.4 GB file costs nothing and appears instantly
        mkfile -n "${kb}k" "$path"
      else
        dd if=/dev/urandom of="$path" bs=1024 count="$kb" 2>/dev/null
      fi
      ;;
  esac

  set_dates "$path" "$days"
  echo "  ${days}d  $(basename "$path")"
}

# copy_file <days ago> <source name> <new name>  -- byte-identical, for duplicates
copy_file() {
  local days="$1" src="$2" new="$3"
  local from="$DIR/$src" dest="$DIR"

  [ -f "$from" ] || from="$(/usr/bin/find "$DIR" -name "$src" -maxdepth 2 | head -n 1)"

  if [ "$FOLDERS" -eq 1 ] && [ "$days" -gt 0 ]; then
    dest="$DIR/$(day_folder "$days")"
    mkdir -p "$dest"
  fi

  cp "$from" "$dest/$new"
  set_dates "$dest/$new" "$days"
  echo "  ${days}d  $new (copy of $src)"
}

# ---------------------------------------------------------------- the contents

echo "Filling $DIR"
echo

# Today. These stay loose in the root, which is the whole point of the demo.
make_file 0 "report.pdf" 840
make_file 0 "Screenshot 2026-08-27 at 09.41.12.png" 1200
make_file 0 "quarterly-figures.xlsx" 96

# Yesterday and the last few days.
make_file 1 "invoice-2026-08.pdf" 220
make_file 1 "keynote-draft.key" 14000
make_file 1 "Screenshot 2026-08-26 at 16.02.55.png" 980
make_file 2 "Figma.dmg" 92000
make_file 2 "node-v24.4.0.pkg" 68000
make_file 3 "sponsors-export.csv" 40
make_file 3 "artifact.zip" 5400

# Last week and older, for the clearing and catch-up demos.
make_file 8  "techorama-deck.pptx" 22000
make_file 12 "logo-pack.zip" 3100
make_file 40 "contract-signed.pdf" 480
make_file 96 "site-backup.zip" 34000
make_file 190 "Xcode_15.4.xip" 74000

# Duplicates, spread around, byte-identical so the review picks them up.
copy_file 8  "artifact.zip" "artifact-1.zip"
copy_file 40 "artifact.zip" "artifact-2.zip"

if [ "$BIG" -eq 1 ]; then
  make_file 5 "recording-raw.mov" 1433600
fi

# Something Tideline must leave alone, to show the skip list working.
mkdir -p "$DIR/Inbox"
echo "keep me" > "$DIR/Inbox/notes.txt"
touch -t "$(date -v-30d +"%Y%m%d%H%M.%S")" "$DIR/Inbox/notes.txt"

if [ "$FOLDERS" -eq 1 ]; then
  for f in "$DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
    [ -d "$f" ] || continue
    d=$(basename "$f")
    touch -t "$(date -j -f "%Y-%m-%d %H:%M:%S" "$d 23:55:00" +"%Y%m%d%H%M.%S")" "$f"
  done
fi

echo
echo "Done. $(/usr/bin/find "$DIR" -type f ! -name "$MARKER" | wc -l | tr -d ' ') files."
echo
echo "Before you record:"
echo "  1. Point Tideline at $DIR under Filing > Folder."
echo "  2. Set Filing > Sort by to 'Date created' or 'Date last modified'."
echo "     macOS stamps 'Date added' at the moment the file lands, so every"
echo "     file here looks like it arrived today under that setting."
if [ "$HAVE_SETFILE" -eq 0 ]; then
  echo "  3. SetFile is missing, so only the modified date is backdated."
  echo "     Use 'Date last modified', or run: xcode-select --install"
fi
echo
echo "Reset between takes:  $0 --dir '$DIR' --reset"