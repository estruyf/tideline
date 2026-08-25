# Filing behaviour

The contract both apps implement. [app/](../app) is the macOS reference
implementation in Swift; [windows/](../windows) is the Windows one in Rust.
Where the two platforms cannot agree, the difference is written down here
rather than discovered later.

Anything in this document is covered by the shared fixtures in
[fixtures/](../fixtures) so the two stay in step without sharing a build.

## A sweep

One sweep reads the root folder — never a subfolder — and decides, per entry,
whether it moves and where to. In order:

1. **Skip the folders we own.** A name matching `^\d{4}-\d{2}(-\d{2})?$` is a
   dated folder this app made. A name matching an enabled type rule is a type
   folder. Neither is ever filed away.
2. **Skip the user's list.** Exact names (`Inbox`) or globs (`*.dmg`).
3. **Skip partial downloads** by extension: `crdownload`, `download`, `part`,
   `partial`, `opdownload`, `tmp`, `temp`, `aria2`.
4. **Skip hidden entries.**
5. **Skip folders** entirely when *file folders too* is off. A `.download`
   bundle is skipped either way.
6. **Read the stamp** under the *sort by* setting (below). No stamp, no move.
7. **Skip anything inside the grace window.** `start_of_day(stamp)` must be
   strictly before `start_of_day(now) - keep_recent_days`.
8. **Skip anything still being written.** See *settling*.
9. **Route it.** An enabled type rule claiming the extension wins and gives the
   folder its name; otherwise the folder is the stamp formatted as `%Y-%m-%d`
   (daily) or `%Y-%m` (monthly).

A type rule decides *where*, never *when* — a `.dmg` downloaded today still
sits loose until it clears the grace window; it just lands in `Installers/`
rather than a dated folder when its time comes.

Entries are processed in ascending name order so a run is reproducible.

## Settling

A file whose contents changed in the last **30 seconds** is assumed to still be
in flight and is left for the next sweep. Between 30 seconds and 10 minutes the
size is read twice, 1.5 s apart, and the file moves only if the two agree — a
slow writer can leave a stale timestamp between flushes. Past 10 minutes it is
taken as settled.

Folders are never settle-checked; a folder's own timestamp says nothing about
what is being written inside it.

## Collisions

Nothing is ever overwritten. `report.pdf` into a folder that already has one
becomes `report-1.pdf`, then `report-2.pdf`, counting up until a name is free.
The extension is preserved; a file with no extension just gains the suffix.

## Dates

| Setting | macOS | Windows |
| --- | --- | --- |
| `added` | `addedToDirectoryDateKey` — Finder's "Date Added" | NTFS creation time |
| `created` | `creationDateKey` | NTFS creation time |
| `modified` | `contentModificationDateKey` | last write time |

**This is the one real divergence.** macOS records when an item arrived *in the
folder it sits in now*, independent of how old the file itself is — an
AirDropped photo keeps the day it was shot as its creation date, so creation
date would file it under the wrong day.

Windows has no equivalent attribute. NTFS creation time is set when the file is
created in that folder, which for a download is the moment it arrived — so for
the case this app exists to handle the two agree. They diverge when a file is
*moved* into the folder from elsewhere on the same volume, where Windows
preserves the original creation time and macOS would record the move.

Consequence: on Windows `added` and `created` resolve to the same value. The
setting is still offered under both names so the two apps' settings files stay
interchangeable, and the UI says what it does.

Each basis falls back when its attribute is missing: `added` → created →
modified, `created` → modified, `modified` → created.

## Clearing

Only folders matching the dated pattern are ever considered — loose files and
folders the user named are invisible to it.

Age is measured from the **end of the period the folder is named for**, not the
folder's own timestamp, which filing bumps every time it drops something new
inside. A folder named `2026-08` is a month old at the end of September, not
at the end of August.

The newest `keep_newest` folders are held back whatever their age, so a long
quiet spell can never empty the root.

Folders go to the recycle bin (macOS Trash, Windows Recycle Bin) — never
`unlink`. A setting the user regrets is a drag back out, not a restore from
backup.

## Review scope

Duplicate, large-file and catch-up reviews look in the root plus the folders
this app made — dated folders and type folders, including the folders of rules
that are currently switched off, since files put there while a rule was on are
still sitting in them. A folder the user made is never opened.

## Preview mode

A preview walks the folder exactly as a real sweep does and reports what it
would have done, having opened nothing for writing. The planner is shared
between the two so the preview and the sweep cannot drift.
