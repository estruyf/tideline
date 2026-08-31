#!/usr/bin/env bash
#
# Drives the running Tideline and captures one PNG per screen into
# public/shots/. Captures are per-window rather than per-region, so each shot
# comes out at 2x with the real rounded corners and a transparent background —
# the promo puts them on a backdrop of its own instead of inheriting whatever
# wallpaper was up on the day.
#
#   ./scripts/capture.sh tour     # the eight tabs, for the Tour composition
#   ./scripts/capture.sh welcome  # the two first-run screens (resets flags)
#   ./scripts/capture.sh menubar  # the menu bar extra, opened
#   ./scripts/capture.sh assets   # the whole README set into assets/1.11.0/
#
# It needs Accessibility for whatever is running it, and it moves the window.
# Point Tideline at a demo folder first: shots of a real Downloads folder have
# somebody's real filenames in them.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(cd "$here/.." && pwd)/public/shots"
repo="$(cd "$here/../.." && pwd)"
domain=be.eliostruyf.Tideline
mkdir -p "$out"

# Where the window is parked. Fixed only so a failed run is reproducible; the
# captures themselves are addressed by window id and do not depend on it.
origin_x=200
origin_y=120

# The window size each profile parks at. The tour crops and spotlights are
# measured against 860x620; the README set matches the 918x678 of the series it
# replaces, so the two live at different sizes on purpose.
tour_size="860 620"
assets_size="918 678"

win_id() {
  swift "$here/windows.swift" Tideline | awk -F'\t' '$4 == "Tideline" { print $1; exit }'
}

# `screencapture -l` is fine for a plain window but cannot isolate a sheet, and
# neither can ScreenCaptureKit — asked for a sheet it hands back the parent
# scaled into the sheet's frame. So a sheet is captured as part of the window it
# belongs to, which is how the rest of the README shows the app anyway.
grab_bin="$here/../.bin/grab"
build_grab() {
  if [ ! -x "$grab_bin" ] || [ "$here/grab.swift" -nt "$grab_bin" ]; then
    mkdir -p "$(dirname "$grab_bin")"
    swiftc -O -o "$grab_bin" "$here/grab.swift"
  fi
}

grab() {
  local id="$2"
  "$grab_bin" "$id" "$1" >/dev/null
  echo "  $(basename "$1")"
}

park_at() {
  osascript -e "tell application \"Tideline\" to activate" \
            -e "delay 0.5" \
            -e "tell application \"System Events\" to tell process \"Tideline\" to set position of window 1 to {$origin_x, $origin_y}" \
            -e "tell application \"System Events\" to tell process \"Tideline\" to set size of window 1 to {$1, $2}" \
    >/dev/null
  sleep 0.6
}

# Pointing the app at a folder other than the one macOS granted clears
# `hasGrantedAccess`, so the lock banner is back on every launch and the pane
# reads "Not measured" until it is answered. The banner's button is the only
# narrow one at the top of the window.
grant_access() {
  osascript >/dev/null 2>&1 <<'''AS'''
tell application "System Events" to tell process "Tideline"
  try
    set b to button 1 of group 1 of window 1
    set s to size of b
    if (item 1 of s) < 150 then click b
  end try
end tell
AS
  sleep 8
}

# Clicks the nth button inside the Reclaim pane's card list, counting from 1.
card() {
  osascript >/dev/null 2>&1 <<AS
tell application "System Events" to tell process "Tideline"
  set xs to {}
  set ys to {}
  set hs to {}
  repeat with b in (buttons of scroll area 1 of group 1 of window 1)
    set bp to position of b
    set bs to size of b
    set end of xs to (item 1 of bp)
    set end of ys to (item 2 of bp)
    set end of hs to (item 2 of bs)
  end repeat
  if (count of xs) < $1 then error "only " & (count of xs) & " card buttons"
  click at {(item $1 of xs) + 20, (item $1 of ys) + ((item $1 of hs) / 2)}
end tell
AS
}

escape() { osascript -e '''tell application "System Events" to key code 53''' >/dev/null; sleep 2; }

shot() {
  local id
  id="$(win_id)"
  [ -n "$id" ] || { echo "no Tideline window" >&2; return 1; }
  screencapture -x -o -l "$id" "$out/$1.png"
  echo "  $1.png"
}

park() {
  osascript -e "tell application \"Tideline\" to activate" \
            -e "delay 0.4" \
            -e "tell application \"System Events\" to tell process \"Tideline\" to set position of window 1 to {$origin_x, $origin_y}" \
    >/dev/null
  sleep 0.4
}

# Clicks the nth row of the sidebar, counting from 1. The rows carry no
# accessibility labels — SwiftUI gives them none — but they are the only wide
# buttons sharing the leftmost x in the window, which picks them out of the
# content buttons beside them whatever tab is showing.
tab() {
  osascript >/dev/null <<AS
tell application "System Events" to tell process "Tideline"
  set xs to {}
  set ys to {}
  set ws to {}
  repeat with b in (buttons of group 1 of window 1)
    set bp to position of b
    set bs to size of b
    set end of xs to (item 1 of bp)
    set end of ys to (item 2 of bp)
    set end of ws to (item 1 of bs)
  end repeat

  set leftmost to 1000000
  repeat with i from 1 to (count of ws)
    if (item i of ws) > 150 and (item i of xs) < leftmost then set leftmost to (item i of xs)
  end repeat

  set cx to {}
  set cy to {}
  repeat with i from 1 to (count of ws)
    if (item i of ws) > 150 and ((item i of xs) - leftmost) < 6 then
      set end of cx to ((item i of xs) + 90)
      set end of cy to ((item i of ys) + 12)
    end if
  end repeat

  if (count of cx) is not 8 then error "found " & (count of cx) & " sidebar rows, expected 8"
  click at {item $1 of cx, item $1 of cy}
end tell
AS
  sleep 1.2
}

case "${1:-tour}" in

tour)
  build_grab
  park_at $tour_size
  grant_access
  # In sidebar order, because the loop presses the nth item. Move out and
  # Routing rules were added between the old entries, so this is not the old
  # list with two names appended.
  names=(overview reclaim move-out schedule filing routing-rules type-folders clearing activity general)
  for i in "${!names[@]}"; do
    tab "$((i + 1))"
    # Reclaim measures the folder when its pane opens, and the figure landing
    # is worth waiting for — a shot of the spinner says nothing.
    [ "${names[$i]}" = "reclaim" ] && sleep 3
    shot "${names[$i]}"
  done
  ;;

welcome)
  # The two screens a fresh install sees. Only the app's own flags are touched:
  # the macOS permission is left exactly as it was, so `Allow Access…` returns
  # straight away and the second screen is the real one, not a mock-up.
  osascript -e 'quit app "Tideline"' >/dev/null 2>&1 || true
  pkill -x Tideline 2>/dev/null || true
  sleep 1.5
  defaults write $domain hasCompletedFirstRun -bool false
  defaults write $domain hasGrantedAccess -bool false
  defaults write $domain hasStartedFiling -bool false
  open -a Tideline
  sleep 3
  park
  shot welcome-permission
  osascript -e 'tell application "System Events" to tell process "Tideline" to click button 2 of group 1 of sheet 1 of window 1' >/dev/null
  sleep 2.5
  shot welcome-first-sweep
  ;;

assets)
  # The README set: the ten panes plus the three review sheets and the menu,
  # into assets/1.12.0/. Sheets are shown inside the window they belong to
  # rather than floating on their own, which is how every other shot on that
  # page shows the app.
  dest="$repo/assets/1.12.0"
  mkdir -p "$dest"
  build_grab
  park_at $assets_size
  grant_access
  id="$(win_id)"

  # In sidebar order, because the loop presses the nth item. Move out and
  # Routing rules were added between the old entries, so this is not the old
  # list with two names appended.
  names=(overview reclaim move-out schedule filing routing-rules type-folders clearing activity general)
  for i in "${!names[@]}"; do
    # A sheet left open by the pane before this one would otherwise sit on top
    # of every shot after it.
    escape
    tab "$((i + 1))"
    if [ "${names[$i]}" = "reclaim" ]; then
      # Big files and old folders are looked for when the pane opens; duplicates
      # wait to be asked. The first card's button therefore says Scan on a
      # folder nobody has asked about yet and Review on one they have, and
      # pressing it does one or the other — so press it, then escape, which
      # closes the review if that is what opened and costs nothing if a scan
      # started instead.
      sleep 6
      card 1
      sleep 12
      escape
      grab "$dest/reclaim-space.png" "$id"
      continue
    fi
    grab "$dest/${names[$i]}.png" "$id"
  done

  # Back to Reclaim for the three reviews. Each button sits on its own card, in
  # the order the pane lists them.
  tab 2
  sleep 8
  for review in 1:review-duplicates 2:review-big-files 3:review-old-folders; do
    card "${review%%:*}"
    sleep 4
    grab "$dest/${review##*:}.png" "$id"
    escape
  done
  ;;

menubar)
  # The extra is not a window, so there is nothing to capture by id until the
  # menu is down; the menu itself is one, owned by the app.
  osascript -e 'tell application "System Events" to tell process "Tideline" to click menu bar item 1 of menu bar 2' >/dev/null
  sleep 1.2
  id="$(swift "$here/windows.swift" Tideline | awk -F'\t' '$4 == "" { print $1; exit }')"
  [ -n "$id" ] || { echo "the menu did not open" >&2; exit 1; }
  build_grab
  grab "${MENUBAR_OUT:-$out}/menubar.png" "$id"
  osascript -e 'tell application "System Events" to key code 53' >/dev/null
  ;;

*)
  echo "usage: $0 [tour|welcome|menubar|assets]" >&2
  exit 1
  ;;
esac

echo "-> $out"
