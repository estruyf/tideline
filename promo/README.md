# The Tideline promo videos

Two cuts, both [Remotion](https://www.remotion.dev) — React rendered to frames,
so the timeline is a table of frame numbers in a `.tsx` file and changing the
pace is changing a number and re-rendering.

| Composition | | |
| --- | --- | --- |
| `Promo` | 30s | The pitch, cut from `tideline-demo.mp4`. Mess, sweep, reclaim, Trash, install |
| `Tour` | 90s | Every screen. First run, the sweep, all six settings panes, Reclaim space, the activity log, the menu bar |

Nothing here is part of the app. It has its own `package.json` and its own
dependencies, and the macOS build still has none.

## Building them

```bash
npm install
npm run assets       # the recording and the app icon into public/
npm run capture      # every window shot, retaken from the running app
npm start            # the Remotion studio, with a scrubbable timeline
npm run render       # out/tideline-promo.mp4  — 1920x1080, 30 fps, ~9.5 MB
npm run render:tour  # out/tideline-tour.mp4   — same shape, ~30 MB
```

`npm run render:small` is the short one at 720p for somewhere with an upload
limit, and `npm run render:gif` makes a silent half-size GIF for a README.

## Where the pictures come from

**The recording**, `tideline-demo.mp4`, is 1920x1080 at 30 fps and so are both
videos — a source frame number and a composition frame number are the same
unit, which is what makes the recording addressable. Every shot names a stretch
of it by frame, and the events in it are fixed points:

| Source frame | |
| --- | --- |
| 50 | Tideline reports **Filed 14 items** |
| 54 | the Finder list turns into dated folders |
| 108 / 140 | the Reclaim space pane opens / the scan lands on 45,9 MB |
| 157 / 196 | the duplicates sheet opens / the copies go to the Trash |
| 228 / 260 | the clearing sheet opens / the folders go to the Trash |

**The window shots** in `public/shots/` are taken by `scripts/capture.sh`, which
drives the running app and captures it per-window rather than per-region: each
PNG is 2x, with the real rounded corners and an alpha channel where the desktop
was, so the tour puts them on a background of its own rather than inheriting
whatever wallpaper was up that day. The same script fills `assets/1.9.0/` for
the root README.

`scripts/grab.swift` is the capture itself, compiled on first use into `.bin/`.
It exists because `screencapture` cannot take a sheet, and it has to be compiled
rather than run through `swift file.swift`: the interpreter has no window-server
connection, and ScreenCaptureKit asserts rather than saying so. `NSApplication.shared`
is the line that gets a plain command-line binary one.

```bash
./scripts/tideline-demo-files.sh --reset         # in the repo root
# point Tideline at ~/Downloads-demo under Filing > Folder,
# and set Sort by to 'Date last modified'
npm run capture -- tour       # the eight tabs, at 860x620, for the Tour
npm run capture -- welcome    # the two first-run screens
npm run capture -- menubar    # the menu, opened
npm run capture -- assets     # the README set, at 918x678, into assets/1.9.0/
```

`tour` and `assets` park the window at different sizes on purpose: the tour's
crops and spotlight rects are measured against 860x620, and the README set
matches the 918x678 of the series it replaces.

Two things the app does that the script has to work around, both worth knowing
if a run comes out blank:

- **Pointing Tideline at a folder other than the one macOS granted clears
  `hasGrantedAccess`**, so the lock banner is back on every launch and every
  pane reads *Not measured* until it is answered. `grant_access` presses it.
- **The first Reclaim card's button says Scan on a folder nobody has asked
  about and Review on one they have**, and pressing it does one or the other.
  The script presses it and then escapes, which closes the review if that is
  what opened and costs nothing if a scan started instead. Without the escape
  the sheet sits on top of every shot after it.

Sheets are captured inside the window they belong to. `screencapture -l` cannot
isolate one — asked for a sheet's id it hands back the parent with the sheet
drawn into it — and neither can ScreenCaptureKit, which returns the parent
scaled into the sheet's frame. In-window is how the rest of the README shows the
app anyway.

`welcome` flips `hasCompletedFirstRun`, `hasGrantedAccess` and
`hasStartedFiling` to replay the first run. It does **not** run `tccutil reset`,
so the real macOS Downloads permission is untouched and `Allow Access…` returns
immediately — the second screen is the app's actual first-sweep estimate, not a
mock-up. Snapshot your settings first, and put them back after:

```bash
defaults export be.eliostruyf.Tideline /tmp/tideline.plist
# ... capture ...
pkill -x Tideline; defaults import be.eliostruyf.Tideline /tmp/tideline.plist
open -a Tideline
```

**Point it at a demo folder before capturing.** A shot of a real Downloads
folder has somebody's real filenames in it, and they are hard to take back out
of a video.

## How a shot is put together

Nothing is sped up. Each shot of the recording **holds** on a frame while its
caption is read, **plays** the part where something happens at somewhere between
a third and two thirds speed, and holds again where it comes to rest — see
`ClipPlan` in [`src/components/Clip.tsx`](src/components/Clip.tsx). Slowing a
whole shot down instead would make the cursor crawl; holding at the ends buys
reading time without touching the pace of the action.

The camera is a crop. [`src/components/Framed.tsx`](src/components/Framed.tsx)
takes a rectangle in the source's own coordinates — the numbers you would read
off a screenshot in Preview — and scales the picture under a window that clips
it. Three rects are named for the recording: `DESKTOP` is the whole frame,
`FINDER` is the file list, `TIDELINE` is the app window. The short promo
interpolates from the first to the second, which is the only camera move in
either video.

Shots sit on one of two stages, and both videos use the same two so a cut
between a screenshot and the recording does not shift the picture sideways.
Wide shots — the Finder list, a settings pane cropped to its content — get the
caption above them. The app window is nearly square and on that stage it would
render at 0.9x, smaller than the app really is, so it gets a column beside it
and the full height of the frame, which puts it back to about 1.2x.

[`Spotlight`](src/components/Spotlight.tsx) points at one control by dimming
everything else. Its rect is in the screenshot's own pixels, measured once off
the PNG. It carries no label: the row it points at already explains itself, and
the caption beside the card says the same thing in the promo's words.

## Rules that matter

- **The recording is never retouched.** No brightness lift, no fake cursor, no
  invented UI. The claims in a caption are the ones the app makes on screen in
  the same shot, and the check that a crop matches the source pixel for pixel is
  `ffmpeg` against a rendered still.
- **The palette is the app's**, from `app/Sources/Tideline/Views/Theme.swift`.
  `ground` is the one addition, a step below `pane` so the picture is the
  brightest thing in the frame. A new colour here means the app grew one first.
- **Every crop edge falls inside a window.** A window with its border sliced off
  reads as a mistake; a crop that starts inside one reads as a zoom. `DESKTOP`
  is the full 1920x1080 for the same reason — anything narrower clips the Finder
  on the left or Tideline on the right.
- **They read without sound.** Set `MUSIC` in `src/theme.ts` to a file in
  `public/` and it plays under both, fading in and out over a second at each
  end. Left `null` the render is silent, which is what a video autoplaying in a
  README wants.
- **The copy sounds like the README.** Plain, specific, no marketing. A caption
  that could go on a landing page for anything else is the wrong caption.

## Re-cutting against a new recording

The frame numbers only mean anything for the take they were cut against, so a
new recording needs the tables in `src/Promo.tsx` and `src/Tour.tsx` rewritten.
Finding the numbers again is mechanical — this prints every frame where a region
of the picture changed:

```bash
ffmpeg -v error -i tideline-demo.mp4 \
  -vf "crop=974:754:906:98,scale=160:-1,tblend=all_mode=difference,signalstats,\
metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
  | paste - - | sed 's/lavfi.signalstats.YAVG=//' \
  | awk '{split($1,a,":"); printf "%s %.2f\n", a[2], $NF}' | awk '$2+0>0.8'
```

The `crop` is the Tideline window; swap in the Finder's rectangle to find the
sweep instead. Check the framing with `npx remotion still src/index.ts Tour
out/check.png --frame=N` before spending the minutes on a full render.
