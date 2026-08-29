# Changelog

All notable changes to Tideline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.11.0] - 2026-08-29

### Added

- **The duplicate review opens a copy in Finder.** The magnifier at the end of
  a row, and **Show in Finder** on a right-click, the same as the big-file
  review has. The copies in a group are byte-for-byte the same, so this is
  never about which one to keep — it is about seeing what the thing actually is
  before agreeing that nine of them can go.

- **The type-folder fields name themselves.** The folder name and extensions
  fields carried their example as their placeholder, which is also what
  VoiceOver read out — so the field for a folder's name announced itself as
  "Installers". They now have a label of their own, hidden because the row
  beside them already says it, and a placeholder that describes what to type
  rather than standing in for one particular answer.

### Fixed

- **The duplicate review kept the wrong copy.** A group could keep
  `report (9).json` while `report (10).json` sat below it, ticked for the Trash.

  The sheet ordered a group by "date added" alone, down to the microsecond.
  Copies that arrived together — ten written in a row, a folder restored from a
  backup, a synced folder landing at once — are microseconds apart in whatever
  order the copying happened to walk them, which is usually alphabetical, and
  that puts `(10)` between `(1)` and `(2)`. Sub-second order is a record of what
  moved the files, not of when they were downloaded.

  Copies are now ordered by day, and within a day by the copy suffix, which is
  the downloader's own count: `(10)` exists only because `(9)` was already
  there, and a name with no suffix came before either. Days apart still separate
  first, so a file downloaded again today still beats the copy left over from
  January. The list also comes out in the same order every time it is scanned,
  which it did not before — the old sort was not stable, so a group with one
  shared timestamp could reshuffle between scans.

## [1.10.0] - 2026-08-29

*Skipped due to a release workflow error*

## [1.9.0] - 2026-08-27

### Added

- **Tideline asks before it does anything.** A fresh install used to open with
  a macOS permission alert already on top of the window, and to be filing
  within seconds of that being answered — a system prompt before the app had
  introduced itself, and a folder rearranged before anyone had agreed that it
  should be.

  It now opens on the window, and on the question. **Allow Access…** is what
  raises the macOS prompt, at a moment you chose and after the sheet has said
  what the permission is for and how far it reaches. Until it is pressed the
  folder is not read at all: not swept, not measured, not scanned. Granting it
  is still not starting — what it buys is the sheet being able to tell you what
  a first sweep would actually do to the folder as it stands right now: *143
  items would move into 12 folders, 4 stay loose*. Then the rule it would
  follow, and two buttons. Nothing is swept until **Start Filing** is pressed: not on launch,
  not when the folder changes, not on the daily timer. **Not Yet** leaves
  everything exactly where it is, and the question is on the Overview pane and
  in the menu bar for whenever you are ready. A preview still runs before the
  answer, because a preview is how the question gets answered. An install that
  predates all this has been filing for weeks and is left alone — an update is
  no reason to stop and ask.

- **Put Everything Back.** Filing was the one thing the app did that you could
  not undo with a single gesture: a year of downloads spread across a hundred
  folders is not something anyone drags back by hand. **Filing › Putting it
  back** lists everything Tideline ever filed, grouped by the folder it would
  come out of, all of it ticked — untick what you would rather leave filed,
  then put the rest back into the root. The folders it empties go to the
  Trash, type folders included: an empty `Installers/` is not something your
  Downloads folder had before Tideline, so putting things back puts that back
  as well. The usual rules hold — a name already taken counts up to
  `report-1.pdf`, folders you made yourself are never opened, nothing is
  deleted, and preview mode previews it.

  Filing switches off once a real restore finishes. The next sweep would move
  back exactly what was just taken out, and that is not an argument worth
  having with your own downloads folder. The switch in the header starts it
  again.

- **Tideline installs with Homebrew.** `brew install --cask
  estruyf/tap/tideline` fetches the same signed and notarized build the release
  page hands out and puts it in `/Applications` — the download, the unzip and
  the drag, done by the thing a lot of people already reach for first.

  It knows the app updates itself, so `brew upgrade` does not reinstall over a
  copy Tideline may have already replaced; `brew upgrade --greedy` hands the job
  back to Homebrew for anyone who would rather it worked that way. It knows the
  app needs macOS 14, which the in-app updater does not, so nobody installs a
  bundle that will not launch. And `brew uninstall --cask --zap tideline`
  removes the same three files the Uninstall sheet names, none of which are in
  your Downloads folder: removing Tideline never touches what Tideline filed.

  Every release updates the cask on its way out, so the tap is never a version
  behind the release page.

### Fixed

- **Opening the app shows the window again.** Tideline decided whether a launch
  was a login item by looking for an `XPC_SERVICE_NAME` in its environment, on
  the theory that only launchd sets one. Launch Services sets one too, for every
  app it starts, so from the second launch onwards every double-click looked
  like a login launch and the app started into the menu bar with no window at
  all — the only way back in was the menu bar icon. It now reads the flag the
  launch notification actually carries for this, so opening the app from Finder,
  the Dock or Launchpad puts the window on screen, while a login item still
  starts with no window and no Dock icon. Closing the window is unchanged: the
  app stays in the menu bar and keeps filing. Each launch says which it was in
  the log file, so a report of "no window appeared" has something to stand on.

### Changed

- **The window says when access is still missing.** Waving away the welcome
  sheet without granting the permission left a window that could not explain
  itself: the status card said *Paused*, the folder card said nothing was
  there, and no control anywhere would ask macOS. The banner across the top now
  covers that state as well as a refusal — a lock rather than a warning
  triangle, since not having asked is not a fault — and carries the one button
  that raises the prompt. The status card leads with it too: what is blocking
  filing outranks whether filing is switched on, so it reads *Waiting for
  permission* and its button asks rather than files.

- **The Overview pane fills the window again.** The card listing the folder
  stretches to the height it is given, so when there is nothing in it to list —
  no access yet, or an empty folder — the pane reads as three cards rather than
  three cards adrift in a void.

- **A refused permission is no longer a dead end.** macOS asks about a
  protected folder once and never again, so a prompt answered with *Don't
  Allow* — or dismissed by accident — left the app with no way to ask a second
  time, and the banner could only point at System Settings and suggest a
  restart. It now offers **Choose Downloads Folder…** as well: picking the
  folder yourself grants the same permission, on the spot, without a trip
  through System Settings or a relaunch. It doubles as the fix for a watched
  folder that has been moved or deleted, since whatever you choose becomes the
  folder Tideline watches.

- **The sheets are the same window now.** Every review sheet — duplicates,
  large files, old folders, catching up, putting things back, the preview and
  the uninstall steps — was drawn on the system's own window grey while the
  window behind it was the app's near-black. The palette reached the accents
  inside them and nothing else, so a sheet read as a panel macOS had put on top
  of Tideline rather than a part of it. They now use the same surfaces the
  window does: the chrome shade behind the header and the buttons, the pane
  shade under the list, and the theme's own hairline between them instead of
  the system divider. The accent goes across with them: a sheet is a window of
  its own, so the tint the window sets never reached it — every confirming
  button and every tick box in a review came up in the system blue, and they
  are the app's yellow now.

## [1.8.0] - 2026-08-27

### Changed

- **The menu bar menu now folds the three reviews into one submenu.** *Review
  Duplicates…*, *Review Large Files…* and *Review Old Folders…* sat in the menu
  as three flat rows asking to be read one at a time. They are now **Duplicates**,
  **Large files** and **Old dated folders** under **Reclaim space**, which is
  what the window has called them all along, with **Review All in Tideline…**
  at the foot, which is still the thing that goes and looks. The submenu quotes
  no figures — opening a menu never starts a scan, so anything it counted would
  be as old as the last time the window was open. *Send Feedback…* and *Check
  for Updates…* moved the same way, into **Help & Updates**, which wears a badge
  when a new version is out. It also carries **Tideline on GitHub**, which was
  nowhere in the menu bar before. The state row gained
  the window's own dot — green watching, yellow filing, red for no access — and
  **Open Downloads Folder** gained ⌘D.

- **Tideline now needs macOS 14.** The version, the folder size and the update
  count sit on the trailing edge of their rows as `NSMenuItem.badge`, which
  arrived in macOS 14; on 13 the same layout would have meant hand-drawn menu
  rows, which cost more than the one version is worth.

## [1.7.0] - 2026-08-26

### Added

- **A notification when a new version is out.** The daily check already said so
  in the window and the menu bar, which is no use with the window shut. *Notify
  me when a new version is out* sits under *Updates* in General, next to the
  switch that decides whether the check happens at all, and it is on by default
  — an update nobody hears about is the same as no update. It goes out once per
  version: a release sits there for weeks, and the same news every morning is
  not news. It is only ever a notice. Nothing is downloaded or installed by it,
  and it never raises a permission prompt of its own — finding an update is not
  a reason to ask — so it appears only where notifications were already allowed.

### Fixed

- **Reclaim space no longer says "11,55 GB of more than 10,66 GB".** Measuring
  the folder stops after 60,000 items and reports what it reached as a floor,
  while the three scans that add up to what could go are not bounded the same
  way. On a folder big enough to hit that cap the amount that could be freed can
  come out larger than the total it is quoted against, which reads as a fault
  rather than as the two different measurements it is. Past the cap the line now
  says how many items are in the way and offers **Scan the folder in full**,
  which walks every file — the same walk, only allowed to finish — and puts the
  real total in place of the floor. It is asked for rather than done every time
  because on a folder holding hundreds of thousands of items it is slow; once
  asked, it holds for the rest of the session, so the next sweep does not
  quietly measure the floor back.

## [1.6.0] - 2026-08-26

### Changed

- **The window has a palette of its own.** `#ffd43b` is the accent now, taken
  from the Demo Time theme along with the surfaces around it — the chrome the
  header band and sidebar sit on, the darker ground the panes use, the cards on
  top of it, and the one border colour every hairline is drawn in. It is a
  bright yellow, so nothing on it is ever white: filled controls carry
  near-black labels, and where the accent has to be *text* on a light
  background it drops to the theme's own darker gold rather than staying
  unreadable. Every token has a light value and a dark one, so the window still
  follows the system appearance — what it no longer follows is the system
  accent colour.

  Colour means something again, rather than everything urgent being orange. The
  accent marks what the app put there and what it is about to touch: filled
  buttons, the selected row, folders it made, files due to move, the figure on
  Reclaim space. Red is kept for faults — no access, a failed sweep, a name that
  cannot be used — so a preview-mode notice and a broken permission no longer
  look alike. Blue is for a button that only navigates, green for running and
  watching.

- **The window has a sidebar instead of five tabs.** Overview and Reclaim space
  at the top, the four rules that decide what happens — Schedule, Filing, Type
  folders, Clearing — grouped under a heading, then the activity log and the
  general settings. Five tabs had reached the point where Filing held four
  unrelated things at once and Clearing held two; a pane each says what each
  one is for. The header shrank to a band: the app's name, what it does in a
  line, and the on/off switch. The foot of the sidebar says which folder all of
  this is about and what it is holding, whichever pane is open, so that answer
  is never a tab away. The window opens at 860×620 rather than 580×640, because
  a sidebar and a pane want the room across rather than down.

- **Overview shows the folder as it stands, not a sketch of one.** The header
  used to draw a tidy Downloads folder — the right idea with the wrong contents,
  since it was the same picture whatever was actually in there. It is now the
  real listing: the type folders, the dated folders newest first, then whatever
  is still loose, each saying what it is and whether the next sweep would move
  it. What it marks as due comes from the same planner a sweep uses, so the
  panel and a sweep cannot disagree about a file. Beside the size, **Waiting for
  you** lists whatever the last scan turned up and links straight into the
  review that deals with it.

- **The menu bar can open the app.** There was only ever **Settings…** down
  among *Open Downloads Folder* and *Send Feedback…*, which was both hard to
  find and the wrong name for a window that is mostly Overview, Reclaim space
  and the activity log. **Open Tideline** (⌘O) now sits at the top of the
  actions and comes up on whichever pane you left. **Settings…** keeps ⌘, and
  earns the name by landing on *Filing*.

- **Open at login moved to where it matters.** It had ended up under *General ›
  Other*, three panes from anything that shows whether the app is running.
  Filing only happens while Tideline is up, so the switch that decides that now
  sits in the status card on Overview, with the reason next to it.

- **Overview dropped the folder-size card.** It said *more than 10,8 GB in
  ~/Downloads* over a bar that, for a tidy folder, is one flat colour — the same
  figure the corner of the sidebar already carries on every pane. **Waiting for
  you** takes the full width instead and says what could actually be done: how
  much could go, and the way through to doing it. The button that re-measures
  moved to the *Downloads right now* header, which is the panel that re-reads the
  folder anyway.

  That figure is counted once across the three scans, the same way Reclaim space
  counts it, so the two panes cannot quote different numbers for the same thing.

- **The two cheap scans no longer wait to be asked.** Landing on Reclaim space
  to find three buttons and no answers was a dead end. Big files and old dated
  folders are found by reading names, sizes and dates — a directory listing and
  a walk, neither of which opens a file — so they now run when the window opens.
  The sidebar badge and Overview's **Waiting for you** are worth having as a
  result: they say what is there before you go looking for it.

  Duplicates keep their button. Matching copies means hashing them, which means
  reading the candidates end to end, and that is not something to start behind
  your back — **Rescan** covers all three when you do ask. A scan is thrown away
  whenever the answer could have moved, so what a card shows is never a figure
  from before the folder shifted underneath it, and a card that looked and found
  nothing now says so instead of offering the button again.

- **Duplicates, big files and old dated folders share one pane.** They were
  spread over Filing and Clearing, which is where their *settings* belong but
  not where the question belongs — all three answer "how much of this could go?"
  **Reclaim space** puts them together, each scanning only when asked and then
  showing what it found and the top few rows of it, with the same review sheets
  as before doing the actual deciding. Nothing about what moves, or where, or
  when has changed; the scans still only read, and everything ticked still goes
  to the Trash.

  **Could be freed**, at the top, adds the three up. They overlap — a big file
  can sit inside a folder old enough to clear, and a duplicate copy can be both
  — so each byte is counted once, by the widest thing that would take it. Adding
  the three totals as they stand would claim more space than the folder has.

## [1.5.0] - 2026-08-25

### Added

- **Review Large Files…**, under **Clearing**. Clearing out goes by age; this
  goes by size. It lists the biggest plain files in the root and in the folders
  Tideline made — dated ones and type folders — largest first, with the folder
  each one sits in and the day it arrived. Every row has a **Show in Finder**
  button, because the question "can this go?" is usually answered by looking at
  it rather than at its name. Nothing starts ticked: a duplicate always leaves a
  copy behind, but a big file is the only copy there is, so each one is a
  deliberate choice. What you tick goes to the Trash, and a dated folder left
  empty by the removals goes with it, as it does after collapsing duplicates.
  **Bigger than** sets the size — 50 MB up to 5 GB, 100 MB to begin with — and
  sits in the sheet as well as in settings, so it can be turned down until the
  list has something in it. Folders you made yourself are never looked in,
  partial downloads and anything on the skip list are never listed, and preview
  mode previews it. Also on the menu bar, as **Review Large Files…**.

## [1.4.0] - 2026-08-25

### Added

- **Review Duplicates…**, under **Filing**. Downloading the same file twice
  leaves `artifact.zip` and `artifact-1.zip`, and the name stops telling you
  anything. This finds them: files in the root and in the folders Tideline made
  whose names match once a copy suffix (`-1`, ` (1)`) is taken off, which are
  also the same size, and which are then read through and compared byte for
  byte. Two files that merely look alike are never called copies. Each group
  starts with the newest kept and the rest ticked for the Trash, a group can
  never have every copy ticked, and nothing goes until the sheet says so. With
  the others gone, the copy that stays can have its plain name back —
  `artifact-1.zip` becomes `artifact.zip`, but only where that name is free —
  which the sheet can switch off. A dated folder left empty by the removals goes
  to the Trash, as it does after catching up; type folders are left alone.
  Preview mode previews it. Also on the menu bar, as **Review Duplicates…**.
- **What the folder holds**, on the **Status** tab: *Downloads holds 14.2 GB*,
  with how much of that is still loose in the root, how much is filed away, and
  in how many folders. Filing tidies a folder; it does not shrink one, and this
  is the line that says so. Measured in the background after every sweep, after
  clearing and after collapsing duplicates, with a button for a fresh look. The
  menu bar carries the same figure, and **General › Show the folder size in the
  menu bar** puts it next to the icon as well — off by default.

### Changed

- **Preview mode** now shows what a sweep would do rather than only writing it
  to the log. **Preview Now** lists every item it would have moved, grouped by
  the folder it would have landed in, in the same kind of sheet **Catch Up…**
  and **Review Old Folders…** already use. The log line is unchanged. In the
  menu bar, **File Downloads Now** reads **Preview a Sweep…** while preview mode
  is on.
- Filing works from a plan it draws up first, rather than deciding as it walks.
  A preview and a real sweep now read the same folder the same way and cannot
  drift apart, since a preview is that plan and a sweep is that plan carried out.

## [1.3.0] - 2026-08-25

### Added

- **Type folders**, under **Filing**. A folder at the root that takes everything
  with one of its extensions instead of the dated folder — switch on
  `Installers` and every `.dmg`, `.pkg`, `.iso` and `.app` lands in
  `Downloads/Installers/`, whatever day it arrived on. Ships with `Installers`,
  `Archives`, `Images`, `Documents`, `Spreadsheets`, `Presentations`, `Audio`,
  `Video` and `Fonts`, **all switched off**, so nothing about filing changes
  until you turn one on. Each can be renamed or re-scoped, and you can add your
  own by naming a folder and listing its extensions. A type folder decides where
  something goes, not when: a `.dmg` downloaded today still stays loose until it
  is older than the **Leave loose in the root** window. Type folders are flat,
  are never filed away themselves, and **Clearing out** leaves them alone —
  only dated folders are ever cleared.
- **Catch Up…**, next to the type folders. Switching a folder on only steers
  what arrives next, so this is how the files already filed by date come into
  line with it: it reads through the dated folders, lists everything the rules
  now claim grouped by where it would go, and moves only what you leave ticked.
  A dated folder left empty by the move goes to the Trash. It obeys the same
  guards a normal sweep does — the skip list, partial downloads, and folders you
  made yourself, which are never opened — and it never overwrites a name already
  taken in the type folder. Preview mode previews it.

## [1.2.0] - 2026-08-24

### Added

- **Check for updates**, straight from the app. Tideline looks at the GitHub
  releases page once a day — and on demand from **General › Updates › Check
  Now** or **Check for Updates…** in the menu bar — and says so on the **Status**
  tab when there is a newer version. **Update & Restart** downloads the release
  build, checks that it is Tideline, that it is the version the release
  advertised, and that it carries the same Developer ID signature and Apple
  notarisation as the running copy, then swaps it in and reopens on the new
  version. A download that fails any of those checks is thrown away, and a copy
  that fails halfway puts the old app straight back. Nothing installs by itself:
  a check only offers. **Skip This Version** silences one release without
  silencing the next, and the daily look can be switched off altogether.

### Fixed

- Files now go by **Date Added** — the day they turned up in the folder — rather
  than the day they were created. An AirDropped photo carries the day it was
  shot as its creation date, so a picture taken yesterday and sent over today
  was filed away the moment it landed instead of staying loose for the day.

### Changed

- **Sort by** gains a third option. *Date added to the folder* is the new
  default; *Date the file was created* keeps the old behaviour for anyone who
  wants it, and *Date last modified* is unchanged.

## [1.1.0] - 2026-08-21

### Added

- **Clearing out**: dated folders can now be sent to the Trash once they are
  older than a month, three months, six months or a year. Manual by default —
  **Review Old Folders…** lists what qualifies with item counts and sizes, all
  ticked, and nothing goes until you press **Move n Folders to Trash**. A
  *Clear on the daily sweep* switch, off by default, makes it unattended as part
  of the once-a-day run; it never rides along with a folder-change sweep.
  Only folders named `YYYY-MM-DD` or `YYYY-MM` — the ones Tideline made itself —
  are ever considered, age is read from the folder's name rather than its
  timestamp, the newest few are always held back whatever their age, and
  everything goes to the Trash rather than being deleted outright. Preview mode
  applies here as well. The menu bar has a **Review Old Folders…** item, which
  opens the window on that sheet rather than clearing out of sight, and greys
  out while clearing is set to *Never*.
- The window is now split into **Status**, **Schedule**, **Filing**,
  **Clearing** and **General** tabs, rather than one long scroll. The app's name
  and the master on/off switch stay above the tabs, as does the no-access
  warning — losing access stops everything, so it should not be hidden behind a
  tab you are not looking at. So does the sketch of how the folder will look,
  which now doubles as a live preview of the folder-name setting over on
  *Filing*.
- The window now suggests opening Tideline at login, since filing only happens
  while the app runs. Accepting or dismissing it once puts the suggestion away
  for good; the switch itself sits on the *Status* tab, beside the run summary.

### Fixed

- The release workflow named its build artifact after the zip inside it, so the
  download and its payload collided on disk and Archive Utility refused it with
  "unsupported format". The artifact is now named separately from the app zip.
- `workflow_dispatch` can attach its build to an existing release tag, so a
  release whose build failed can be repaired without cutting a new version.

## [1.0.0] - 2026-08-20

First public release.

### Added

- Files everything in `~/Downloads` older than today into folders named for the
  day it arrived, leaving today's downloads loose in the root under their real
  names.
- Menu bar app with a status view: whether filing is on, when it last ran, what
  it moved, and when the next sweep is due. **File Now** runs one immediately.
- Scheduling, in any combination — on folder change (sweeping once things go
  quiet for 8 seconds), once a day at a time you pick (00:05 by default), at app
  start to cover a run missed while the Mac was off, and open at login. A run
  missed during sleep fires on wake.
- Configurable filing: any folder, not just `~/Downloads`; a grace window of
  today, today and yesterday, the last 3 days or the last week; one folder per
  day (`2026-08-19`) or per month (`2026-08`); sorting by date added or date
  last modified; and whether downloaded folders move like files.
- Preview mode, which logs what would move and touches nothing.
- Exclusions by exact name (`Inbox`) or pattern (`*.dmg`), on top of the
  built-in ones: hidden files, partial downloads (`.crdownload`, `.download`,
  `.part`, `.partial`, `.opdownload`, `.tmp`, `.temp`, `.aria2` and Safari's
  `.download` bundles), anything written to in the last 30 seconds, and the
  dated folders the app created itself.
- Never overwrites: a name already taken in the target folder becomes
  `report-1.pdf`, `report-2.pdf`, and so on.
- Recent activity list of the last dozen moves, with a full log at
  `~/Library/Logs/Tideline.log`.
- Uninstall view that removes the app's own files and settings.
- Universal build (Apple silicon and Intel), signed with a Developer ID,
  notarized and stapled.

### Notes

- Requires macOS 13 or later.
- Runs as a background app: no Dock icon until the window is opened.
- Asks for access to your Downloads folder on first launch. Because it is a
  signed app rather than a script, macOS scopes that permission to Tideline
  alone instead of to `bash` or your terminal.

[1.11.0]: https://github.com/estruyf/tideline/compare/v1.9.0...v1.11.0
[1.9.0]: https://github.com/estruyf/tideline/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/estruyf/tideline/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/estruyf/tideline/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/estruyf/tideline/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/estruyf/tideline/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/estruyf/tideline/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/estruyf/tideline/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/estruyf/tideline/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/estruyf/tideline/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/estruyf/tideline/releases/tag/v1.0.0
