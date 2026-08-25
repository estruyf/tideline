# Tideline for Windows

The Windows build. Same rules as the macOS app, a separate implementation:
Rust for the engine, [Tauri v2](https://tauri.app) for the window and the tray.

The macOS app in [`app/`](../app) is untouched by any of this and stays a
SwiftPM executable.

## Why not share the Swift

The macOS engine looks portable — most of it imports only Foundation — but every
file leans on something Darwin-only: `addedToDirectoryDateKey`, `trashItem`,
`DispatchSource.makeFileSystemObjectSource`, `CryptoKit`. Sharing it would have
saved roughly 1,500 of 6,500 lines and cost a Swift-on-Windows toolchain, a
WinUI binding layer instead of SwiftUI, and ~40 MB of Swift runtime DLLs beside
an app whose entire pitch is that it is 1.7 MB with no runtime.

So the two share a *contract* rather than a build:
[`docs/behaviour.md`](../docs/behaviour.md) in prose and
[`fixtures/sweep-cases.json`](../fixtures) in cases both are expected to pass.

## Layout

```
windows/
├── src/                        the window — plain HTML, CSS and JS, no framework
└── src-tauri/
    ├── src/
    │   ├── lib.rs              tray, schedule, commands — when a sweep happens
    │   ├── app_info.rs         name, author and the links the About tab opens
    │   └── settings_store.rs   preferences, as JSON under %APPDATA%
    └── crates/tideline-core/   the engine — which files move, and where to
```

`tideline-core` is where the rules live and it knows nothing about Tauri. It
splits in two on purpose:

- `organizer::plan` is **pure** — handed a list of `Entry` values and a moment,
  it answers what would move. No filesystem, so the shared fixtures can drive it
  directly.
- `sweep` does the I/O — reads the folder into `Entry` values, and carries the
  moves out.

That split is also why a preview and a real sweep cannot drift: both call the
same `plan`.

## Building

Needs [Rust](https://rustup.rs) and Node 22. On Windows you also need the MSVC
build tools and WebView2 — WebView2 ships with Windows 11 and with Windows 10
from 21H2, so in practice only the build tools are a download.

```powershell
cd windows
npm ci
npx tauri dev      # run it
npx tauri build    # NSIS installer in src-tauri/target/release/bundle/nsis
```

**The UI can be developed on a Mac.** `npx tauri dev` on macOS builds the same
Rust and the same front end into a macOS window — handy for iterating on the
layout without a Windows machine. The Windows-only paths (the Recycle Bin,
`FILE_ATTRIBUTE_HIDDEN`) are `cfg`-gated and inert there, so anything touching
them still has to be tried on Windows.

Cross-*building* from macOS does not work: Tauri's build script needs a Windows
resource compiler to embed the icon, and linking needs the MSVC toolchain. The
[Windows workflow](../.github/workflows/windows.yml) builds on `windows-latest`,
which is the supported path.

## Testing

```bash
cd windows/src-tauri
cargo test --workspace          # 47 tests
cargo clippy -p tideline-core -- -D warnings
cargo fmt --all -- --check
```

The engine's rules are also checked against the Windows target from any
platform, which is what catches the `cfg(windows)` branches:

```bash
cargo check -p tideline-core --target x86_64-pc-windows-msvc
```

## Where the platforms differ

Written up in full in [`docs/behaviour.md`](../docs/behaviour.md). The three
that matter:

| | macOS | Windows |
| --- | --- | --- |
| Date added | a real per-folder attribute | no equivalent; creation time stands in |
| Permission to read Downloads | a prompt, and an orange banner if refused | none needed |
| Deleting | Trash | Recycle Bin |

The permission difference removes a whole section of the macOS app — there is no
prompt to explain and no Privacy Settings to deep-link to. It also removes the
macOS README's argument for why this is an app rather than a script; on Windows
a scheduled task would genuinely work, and the tray app earns its place on the
watching and the reviews instead.

## What is built

- The filing engine, complete: the grace window, daily and monthly folders, type
  folders, the skip list with glob patterns, partial-download and settling
  rules, and never overwriting a name.
- Preview mode.
- The window: Status, Filing, Schedule and About.
- **About**, with the version, the WebView2 build drawing the window, the links
  to the repository and the issue tracker, and where the settings file lives.
  The window asks for a link by name and `app_info` decides what that means, so
  the page cannot point the browser at something of its own.
- The tray icon and its menu.
- The daily schedule, including catching up a run missed while the machine was
  off. It polls once a minute rather than setting a timer, because a long timer
  drifts across sleep and Windows is generous with sleep.
- Settings, saved to `%APPDATA%\Tideline\settings.json` — written to one side
  and renamed, so a crash mid-write cannot destroy them.
- **Start at sign-in**, from the Schedule tab or the tray. Windows is the source
  of truth, not the settings file: the Startup tab in Task Manager can switch it
  off behind the app's back, so the state is read back from the OS on every
  launch and after every toggle. Started that way the app comes up in the tray
  with no window — it is passed `--minimized`.

## What is not

In rough order of how much each is worth doing next:

1. **Folder watching** — `watch_folder` is stored and honoured by nothing.
   Wants `ReadDirectoryChangesW` (the `notify` crate) plus the macOS app's
   8-second quiet period.
2. **Clearing** — `Cleaner.swift`. The rules are already written down in
   `docs/behaviour.md`; the Recycle Bin call is wired up as `sweep::recycle`.
3. **Duplicates** — `Deduper.swift`. Needs a SHA-256 (`sha2`) in place of
   CryptoKit.
4. **Large files** and **Catch Up** — `Weigher.swift`, `Regrouper.swift`.
5. **Notifications** on a completed sweep — the plugin is registered,
   `notify_on_move` is stored, nothing sends one yet.
6. **The updater** — the biggest one, and the one with a cost attached. See
   below.

## Signing, and why the updater is last

An unsigned installer downloaded from GitHub gets a SmartScreen warning, and
reputation is per-certificate. The options are
[Azure Trusted Signing](https://learn.microsoft.com/azure/trusted-signing/)
(~$10/month, needs a verified organisation or an individual identity three or
more years old) or an EV certificate (~$300–400/year).

Publishing through **winget** avoids most of it and is where Windows users
expect to find something like this — worth doing before building a self-updater
that has to verify its own signature the way the macOS one does.
