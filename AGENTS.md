# Tideline

A macOS menu-bar app that files older downloads into folders named for the day
they arrived. Native Swift, SwiftPM, no dependencies — a release is about 3 MB
to download and 9.6 MB unpacked, because the bundle is universal. That is a
feature, not an accident.

A Windows build lives in `windows/`: the same filing rules rewritten in Rust,
behind a Tauri v2 shell. It builds and its tests pass. The **filing engine is
complete** — grace window, daily and monthly folders, type folders, the skip
list, settling and collision rules. Clearing, duplicates, the big-file review,
catch-up, folder watching and the updater are **not ported yet**;
`windows/README.md` ranks what is left.

The two apps share no code, only a contract. Nothing in `windows/` should ever
be a reason to change `app/`, or the reverse — see `docs/behaviour.md`.

## Layout

| Path | |
| --- | --- |
| `app/Sources/Tideline/` | The app. `Organizer` files, `Cleaner` clears, `Deduper` collapses copies, `Weigher` finds big files, `Regrouper` catches up, `RuleInspector` counts what each routing rule catches, `Controller` schedules |
| `app/Sources/Tideline/Views/` | SwiftUI window, one file per tab or sheet |
| `app/Package.swift` | One executable target, macOS 14+, zero dependencies |
| `app/build.sh` | Build, bundle, icon, sign, notarize, staple, zip, disk image |
| `app/Tools/make-dmg-layout.sh` | Records the disk image's window layout, by hand, into `app/Resources/dmg/DS_Store` |
| `app/Resources/Info.plist` | Bundle template; `__VERSION__` / `__BUILD__` substituted at build time |
| `app/Resources/dmg/DS_Store` | The disk image's window layout, recorded once by `app/Tools/make-dmg-layout.sh` and committed so a release build never has to drive Finder |
| `windows/src-tauri/crates/tideline-core/` | The Rust filing engine. `organizer` holds the rules and is pure; `sweep` does the I/O |
| `windows/src-tauri/src/` | The Tauri shell — tray, schedule, commands, settings on disk |
| `windows/src/` | The window: plain HTML, CSS and JS, no framework and no build step |
| `docs/behaviour.md` | The filing contract both platforms implement |
| `docs/*.md` | Technical documentation, for whoever builds or releases the app. Anything a **user** needs is on the website in `site/docs/`, not here |
| `fixtures/sweep-cases.json` | The contract as runnable cases. Add a rule here first |
| `homebrew/` | The Homebrew cask and the script that stamps it into `estruyf/homebrew-tap` |
| `site/` | The website and the end-user manual: hand-written HTML and CSS, no framework and no build step. `stage.sh` folds the newest `assets/<version>/` in as `assets/shots/`, which is why no page names a version, and copies `assets/tour.mp4` beside it |
| `scripts/dmg-background.html` | The source of the disk image background. `scripts/render-dmg-background.sh` shoots it at 1x and 2x and folds both into `assets/dmg/background.tiff` |
| `scripts/pitch-image.html` | The source of the before/after banner. `scripts/render-pitch.sh` shoots it headless into `assets/pitch.jpg` and `assets/pitch-light.jpg` — edit the HTML, never the JPEGs |
| `promo/` | Two promo videos in Remotion — a thirty-second cut of the screen recording, and a ninety-second tour built from window captures `promo/scripts/capture.sh` takes off the running app. Its own `package.json` and its own dependencies; the app still has none |
| `.claude/skills/screenshots/` | How the README pictures are retaken off the running app, and what to check afterwards |
| `docs/building.md`, `docs/signing.md`, `docs/releasing.md`, `docs/homebrew.md` | Build, distribution, release and cask notes |
| `windows/README.md` | Building on Windows, what is ported, what is not |
| `app/.build/`, `app/dist/`, `windows/**/target/`, `promo/out/`, `_site/`, `old-scripts/` | Ignored by git; never edit or commit |

## Commands

```bash
npm run build            # universal binary into app/dist/
npm run build:install    # build, copy to /Applications, launch it
npm run build:dmg        # build, then wrap it in app/dist/Tideline.dmg
npm run dmg:background   # re-render assets/dmg/background.tiff from the HTML
npm run dmg:layout       # re-record app/Resources/dmg/DS_Store (needs a real Finder)
npm run logs             # tail ~/Library/Logs/Tideline.log
npm run quit             # quit the running app
npm run clean            # throw away build artefacts
npm version patch        # bump, rebuild, commit and tag

npm run win:test         # the Rust workspace: 65 tests
npm run win:check        # type-check the engine against the Windows target
npm run win:dev          # run the Tauri app (works on a Mac too, see below)
npm run win:build        # NSIS installer — Windows only

npm run site             # stage the website into _site/ and serve it on :8080
npm run site:stage       # stage it without serving — what the Pages workflow runs
```

`swift run` is not a useful way to test a change: it starts the executable
without a bundle, so there is no bundle identity and no scoped Downloads
permission. Build the app and run that instead.

## Verifying a change

There is no Swift test target. Confirm behaviour by running the real bundle:

1. `npm run build:install`
2. Switch on **Preview mode** under **Filing** — sweeps then report what they
   would do without touching a file.
3. `npm run logs` and watch a sweep decide.

The Rust side does have tests — `npm run win:test` runs all 65. The rules are
pure functions taking a list of entries and a moment, so a rule change is
provable without a filesystem; only `sweep.rs` needs a real folder.

The first-run flow — the permission prompt and the question that gates
filing — only happens once per machine. `docs/building.md` has the commands
that put the app back to knowing nothing about you.

`npm run win:dev` works on a Mac: it builds the same Rust and the same front end
into a macOS window, which is enough to iterate on the layout. The `cfg(windows)`
paths — the Recycle Bin, `FILE_ATTRIBUTE_HIDDEN` — are inert there and still
need real hardware. `npm run win:check` compiles them without running them.

Cross-*building* the installer from macOS does not work; CI builds it on
`windows-latest`.

## Rules that matter

- **`docs/behaviour.md` is the contract, and `fixtures/sweep-cases.json` is the
  executable half of it.** Any change to what moves, when, or where it lands is
  a change to the document and a case in the fixtures first, then to both
  implementations. They exist so the Swift and Rust engines cannot quietly
  drift. Only the Rust side runs the fixtures today; the Swift planner reads the
  filesystem directly and needs the same pure/IO split before it can.
- **Nothing is ever deleted.** Removals go to the Trash on macOS
  (`FileManager.trashItem`) and the Recycle Bin on Windows (`sweep::recycle`),
  never `unlink`. A setting someone regrets should be a drag back out, not a
  restore from backup.
- **Nothing is ever overwritten.** A name collision counts up: `report.pdf`,
  `report-1.pdf`, `report-2.pdf`.
- **Preview mode (`Settings.dryRun`) binds every destructive feature.** Filing,
  clearing, duplicate collapsing, large-file review and catch-up all have to
  honour it. A new feature that moves or trashes anything gets a preview path
  before it gets a button.
- **The disk image is assembled from committed pieces, and the layout is
  recorded rather than built.** `build.sh --dmg` copies
  `assets/dmg/background.tiff` and `app/Resources/dmg/DS_Store` into a staging
  folder and hands it to `hdiutil`; it drives no Finder, which is the only
  reason it runs in CI. Re-record the layout with `npm run dmg:layout` when the
  artwork or the icon positions change, and check the result by building an
  image and opening it — the live Finder window that script leaves behind is not
  a reliable preview. The volume is always named `Tideline`, with no version in
  it, because the recorded layout refers to the background through the volume.
- **A release attaches two downloads, and they are not interchangeable.** The
  disk image is for a person; the zip is what the in-app updater fetches and
  what the Homebrew cask reads. `Updater.macAsset` matches the zip by name and
  falls back to any `.zip` with *tideline* in it, so the image can never be
  picked up by mistake — and renaming the zip is a change to that function.
- **`package.json` is the macOS version, and the only one.** `build.sh` reads it
  into the plist — never hand-edit `CFBundleShortVersionString`. The release
  workflow refuses a tag that disagrees with it. The Windows build versions
  itself independently in `windows/package.json`, `tauri.conf.json` and its
  `Cargo.toml`, and sits at `0.1.0` until it reaches parity; the two ship on
  separate schedules and separate workflows.
- **The macOS app has no dependencies.** Neither SwiftPM nor npm; the root
  `package.json` holds shortcuts to `build.sh` and to the website's staging
  script, and nothing more. The Windows build
  necessarily has some (Tauri, chrono, serde, trash), but the same instinct
  applies — the front end is hand-written HTML and CSS rather than a framework,
  and it should stay that way.
- **The app is a background app** (`LSUIElement`). It has no Dock icon until the
  window is opened.

## Code conventions

- `Controller` is `@MainActor` and owns the schedule, the watcher and the run
  state. Filing runs on `runQueue`; anything that merely reads — measuring the
  folder, hashing for duplicates — goes on `inspectQueue` so a long look never
  delays a sweep.
- Settings live in `Settings.swift`, backed by `UserDefaults`. A new preference
  is a `Key`, a default in the registration dictionary, and an `@Published`
  property whose `didSet` calls `store(_:_:)` — which posts `.settingsChanged`
  for you.
- Anything persisted to disk (`history.json`) decodes leniently, with
  `decodeIfPresent` and a fallback, so an upgrade never blanks someone's
  activity list.
- **Colour comes from `Views/Theme.swift`, never from a literal or a system
  semantic.** `#ffd43b` is the accent and it is a filled-surface colour — its
  labels are `Theme.onAccent`, and accent-as-text is `Theme.accentText` so the
  light appearance can darken it. Keep the meanings apart: accent for what the
  app put there or is about to touch, `danger` for faults, `link` for a button
  that only navigates, `success` for running. Every token carries a light value
  and a dark one, so a new one is added in pairs.
- **Nothing in the window is smaller than 12pt.** `.callout` is the floor —
  `.caption` and `.caption2` are 10pt and are not used, whatever the role.
  Explanatory prose goes through `.explanation()` in `Views/Panel.swift` so the
  sentence under a heading is named rather than sized by hand; secondary weight
  and monospacing sit on `.callout` alongside it. A column cut to fit 10pt text
  needs about a fifth more width at 12.
- Comments explain **why**, in prose, in full sentences. The codebase reads like
  its own documentation — match that rather than annotating what the next line
  already says.
- The same voice runs through the README, the changelog and the UI strings:
  plain, specific, no marketing. New user-facing text should sound like the text
  already there.

On the Rust side:

- `tideline-core` knows nothing about Tauri, and `organizer.rs` knows nothing
  about the filesystem. A rule belongs in `plan`, which takes entries and a
  moment and returns what would move; reading a folder belongs in `sweep.rs`.
  That split is why a preview and a real sweep cannot disagree.
- `now` is passed in, never read inside a rule, so midnight and the grace window
  are testable without waiting for either.
- `cargo fmt` and `cargo clippy -- -D warnings` both gate CI. Run them before
  pushing; the same prose-comment convention applies.

## Shipping a change

- Add a **Keep a Changelog** entry under a new version heading in `CHANGELOG.md`,
  written the way the existing entries are — what it does, and why it behaves
  the way it does.
- **The website is the manual, and `README.md` is the pitch.** A change visible
  in the window or the menu bar is written up in `site/docs/`; the README only
  changes when the pitch, the install or the list of what it does changes. They
  were one document until the site existed, so resist writing the detail twice.
  Also update `docs/behaviour.md` and `fixtures/sweep-cases.json` if it touches
  the filing rules, and `windows/README.md` if it changes what is ported.
- **A new screenshot set goes in `assets/<version>/` and nothing else needs
  editing.** `site/stage.sh` picks the highest-numbered folder, so the pages
  follow it on their own — that is why they ask for `assets/shots/`. Keep the
  filenames the same or a page loses its picture, which `stage.sh` will fail on
  rather than publish.
- **The pitch banner is generated, not drawn.** It is two Finder windows in
  HTML — the same folder before and after — so the file lists have to reconcile:
  every file on the left is either still loose on the right or inside the folder
  for the day it arrived, and the item counts say which. Change one list and
  change the other. `./scripts/render-pitch.sh` re-renders both themes.
- **`assets/tour.mp4` is the rendered tour, and it is committed on purpose.**
  `promo/out/` stays ignored because it also holds the 28 MB master and the
  promo cut; the 4 MB 720p tour is a shipped asset like the screenshots, since
  the Pages workflow only ever sees what is in the repository. Re-render it with
  `npm run render:tour` in `promo/`, then copy the web cut over this one and
  refresh `assets/tour-poster.jpg` from a frame of it.
- Commit messages are short and descriptive, in the imperative or past tense —
  match `git log`. Version bumps are their own commit, made by `npm version`.
- Releasing macOS is `npm version patch`, push the tag, then publish the release
  on GitHub; `release.yml` signs, notarizes and staples both the zip and the
  disk image, attaches the two of them, and stamps the Homebrew cask into the
  tap. The in-app updater depends on the zip's asset name and the notarization —
  `docs/releasing.md` has the details.
- **The cask is `homebrew/tideline.rb`, and it is generated into the tap, not
  edited there.** A change to it lands on the next release. `depends_on macos:`
  has to move whenever `LSMinimumSystemVersion` does, and the `zap` paths
  whenever `UninstallView` does — those are the two places it can silently fall
  out of step with the app. `docs/homebrew.md` says why each stanza is there.
- Windows has its own workflow, `windows.yml`. It tests on every push touching
  `windows/` or `fixtures/`, and builds the installer on demand. It is
  deliberately not tied to the release tag while the port is behind; make it
  `release: types: [published]` once it reaches parity.
