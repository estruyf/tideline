# Changelog

All notable changes to Tideline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The window now suggests opening Tideline at login, since filing only happens
  while the app runs. Accepting or dismissing it once puts the suggestion away
  for good; the switch itself stays under *When it runs*.

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

[Unreleased]: https://github.com/estruyf/tideline/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/estruyf/tideline/releases/tag/v1.0.0
