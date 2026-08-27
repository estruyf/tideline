---
name: screenshots
description: Retake the Tideline window screenshots off the running app and repoint the README at them. Use when asked to update the screenshots, refresh the pictures in the README, or prepare the shots for a new version.
---

# Screenshots for the README

Every picture in `README.md` except the poster and the macOS permission dialog is
taken by driving the running app and capturing its window. The whole set is one
command per profile, so a release that changed the window is a re-run and a
find-and-replace, not an afternoon in Preview.

The script is [`promo/scripts/capture.sh`](../../../promo/scripts/capture.sh).
It lives in `promo/` because the promo videos need the same shots, but its
`assets` profile writes the README set — parked at 918x678, captured at 2x, so
every PNG lands at 1836x1356 and matches the series before it.

## The set

`assets` writes eleven files into `assets/<version>/`:

| File | Where it appears |
| --- | --- |
| `overview.png` | the window, near the top of the README |
| `reclaim-space.png` | Reclaim space |
| `review-duplicates.png`, `review-big-files.png`, `review-old-folders.png` | the three review sheets, shown inside the window |
| `schedule.png`, `filing.png`, `type-folders.png`, `clearing.png`, `general.png` | the settings panes |
| `activity.png` | nothing yet — captured because the tour uses it |

Two more are not part of that run:

- `menubar.png` comes from the `menubar` profile, which has to point its output
  at the version folder itself.
- `permission.png` is macOS asking for the Downloads folder, not a Tideline
  window, so no script can drive it. Take it by hand (⇧⌘4, space, click the
  dialog) or carry the previous one forward with `cp`; it only changes when
  Apple redraws the prompt.

## Before capturing

1. **Install the build being shot.** `npm run build:install` — the General pane
   shows the version number, so shots of the old build date the whole page.
2. **Point the app at demo data.** `./scripts/tideline-demo-files.sh --reset`,
   then **Filing › Folder** → `~/Downloads-demo`. Never capture a real Downloads
   folder: those are somebody's real filenames and they end up in a README that
   is hard to take back.
3. **Snapshot the settings**, because the run clicks through the app and the
   `welcome` profile rewrites flags:
   ```bash
   defaults export be.eliostruyf.Tideline /tmp/tideline.plist
   ```
4. **Set the version folder.** `dest=` in the `assets` case of `capture.sh` is
   written out in full; bump it to the version in `package.json` before running.
5. Accessibility has to be granted to whatever runs the script — it moves,
   resizes and clicks the window. macOS will prompt the first time.

## The run

```bash
cd promo
npm run capture -- assets                                       # the eight panes and the three sheets
MENUBAR_OUT="$(cd .. && pwd)/assets/<version>" npm run capture -- menubar
```

It takes a couple of minutes: the Reclaim pane measures the folder when it
opens, and duplicates are only matched when asked, so the script waits on both
rather than photographing a spinner.

`npm run capture -- welcome` replays the first run for the two welcome screens.
They are not in the README today, and it flips `hasCompletedFirstRun`,
`hasGrantedAccess` and `hasStartedFiling` to do it — only run it if the first-run
flow itself changed, and restore afterwards:

```bash
pkill -x Tideline; defaults import be.eliostruyf.Tideline /tmp/tideline.plist; open -a Tideline
```

## Then the README

Repoint the links at the new folder and check that every one of them resolves:

```bash
sed -i '' 's|/assets/1.9.0/|/assets/1.10.0/|g' README.md
grep -o '(\./assets/[^)]*)' README.md | tr -d '()' | while read -r p; do
  [ -f "$p" ] || echo "missing: $p"
done
```

Then read the alt text beside each changed shot. It describes what is in the
picture — a pane that grew a control describes something that is no longer
there, and the alt text is the half of the README nobody re-reads.

Keep the old version folders. Tags point at them, so `assets/1.6.0/` is still
serving the README as it was at 1.6.0.

## When a run comes out wrong

- **Every pane reads *Not measured* and the lock banner is up.** Pointing the app
  at a folder other than the one macOS granted clears `hasGrantedAccess`.
  `grant_access` in the script presses the banner; if the shots still show it,
  answer the prompt by hand once and run again.
- **A sheet sits on top of the shots after it.** The script escapes between
  panes for exactly this. A shot with a stray sheet means a wait was too short —
  the panes that scan are the slow ones.
- **The first Reclaim card says Scan on one run and Review on the next**,
  depending on whether duplicates have been matched yet. The script presses it
  and escapes, which costs nothing either way.
- **A shot is 1720x1240 rather than 1836x1356.** That is the tour's window size —
  the `tour` profile ran instead of `assets`.
