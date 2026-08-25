# Changelog — Tideline for Windows

The Windows build versions itself independently of the macOS app, which is
tracked in [`../CHANGELOG.md`](../CHANGELOG.md). It stays below 1.0 until it
reaches parity; [`README.md`](README.md) lists what is still missing.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-25

The first Windows build. The filing engine is complete and agrees with the
macOS app case for case; everything built on top of it is not ported yet.

### Added

- **The filing engine**, rewritten in Rust as `tideline-core`: the grace window,
  daily and monthly folders, type folders, the skip list with glob patterns, the
  partial-download and settling rules, and counting a name up rather than
  overwriting it. `organizer::plan` is a pure function of a list of entries and a
  moment, so it is driven directly by
  [`fixtures/sweep-cases.json`](../fixtures) — the same cases the contract in
  [`docs/behaviour.md`](../docs/behaviour.md) describes in prose. That is what
  keeps the two platforms from drifting.
- **Preview mode**, on the same footing as it has on macOS: a preview and a real
  sweep both call `plan`, so they cannot disagree about what would move.
- **The window** — Status, Filing, Schedule and About — written as plain HTML,
  CSS and JavaScript. No framework and no build step, for the same reason the
  macOS app has no dependencies.
- **The tray icon and its menu**, for sweeping now and opening the window.
- **The daily schedule**, including catching up a run missed while the machine
  was off. It polls once a minute instead of setting a long timer, because a
  timer drifts across sleep and Windows sleeps often.
- **Start at sign-in**, from the Schedule tab or the tray. Windows is the source
  of truth rather than the settings file — the Startup tab in Task Manager can
  switch it off behind the app's back — so the state is read back from the OS on
  every launch and after every toggle. Started that way the app comes up in the
  tray with no window.
- **Settings**, saved to `%APPDATA%\Tideline\settings.json`, written to one side
  and renamed so a crash mid-write cannot destroy them.

### Notes

- Requires Windows 10 21H2 or later, for WebView2. Windows 11 has it already.
- Deleting goes to the Recycle Bin, never `unlink`, as it goes to the Trash on
  macOS.
- There is no permission prompt: reading Downloads needs no grant on Windows, so
  the whole section the macOS app spends on that is absent here.
- Where macOS has a real per-folder date-added attribute, Windows has no
  equivalent and creation time stands in.
- **The installer is not signed yet**, so SmartScreen will warn on first run.
  Signing, and the self-updater that depends on it, are the last things on the
  list — `README.md` explains why.
- Not ported yet: folder watching, clearing, duplicates, large-file review,
  catch-up, notifications and the updater.

[0.1.0]: https://github.com/estruyf/tideline/releases/tag/win-v0.1.0
