# Changelog

All notable changes to Tideline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.0]: https://github.com/estruyf/tideline/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/estruyf/tideline/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/estruyf/tideline/releases/tag/v1.0.0
