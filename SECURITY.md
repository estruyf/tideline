# Security policy

Tideline moves files around in your Downloads folder and updates itself in
place, so it is worth being careful with. This page says which versions get
fixes, how to report something, and what the app already does and does not do.

## Supported versions

| Version | Supported |
| --- | --- |
| The latest macOS release | Yes |
| Anything older | No — update first, then report |
| The Windows port (`windows/`, 0.1.0) | Not yet — it has no releases and is behind the macOS app |

There is one supported macOS version at a time: the newest one on the
[releases page](https://github.com/estruyf/tideline/releases/latest). Fixes ship
as a new release rather than as a patch to an old one, and the in-app updater
brings you to it. macOS 14 or later.

## Reporting a vulnerability

**Report it privately, not as an issue.**
[Open a draft advisory](https://github.com/estruyf/tideline/security/advisories/new)
— that is GitHub's private reporting form, visible only to you and the
maintainer. If it will not open for you, mail the address on
[github.com/estruyf](https://github.com/estruyf) and say the subject is a
Tideline security report.

Useful things to include: the version from **General → About**, your macOS
version, what an attacker would have to already have, and the smallest set of
steps that shows it. A folder layout that reproduces it is worth more than a
description of one.

What happens next: an acknowledgement within a few days, and a first assessment
— accepted, needs more information, or out of scope, with the reasoning — within
a week. Accepted reports are fixed in the next release, credited in
`CHANGELOG.md` and in the advisory unless you would rather not be. Please give
the fix a chance to ship before writing it up publicly; if it is taking too
long, say so and we will agree on a date.

## In scope

- **Filing.** Anything that makes Tideline write outside the folder it was
  pointed at, follow a symlink out of it, overwrite a file instead of counting
  the name up, or destroy data rather than move it to the Trash.
- **The updater.** Anything that gets an unsigned, downgraded or substituted
  build past the checks in `Updater.swift`, or that reads the release feed into
  something worse than a version number and a URL.
- **The release pipeline.** Signing, notarization, the workflow in
  `.github/workflows/release.yml`, and the Homebrew cask in `homebrew/`.
- **The Rust engine** in `windows/src-tauri/`, even though nothing ships from it
  yet — a rule that mis-files is a bug in the contract both apps implement.

## Out of scope

- Behaviour the app documents and asks about on first run: it files older
  downloads into dated folders, and with the relevant settings on it also
  clears, collapses duplicates and reviews large files. `docs/behaviour.md` is
  the contract. Disagreeing with a default is a feature request.
- Anything that needs code already running as you, or physical access to an
  unlocked Mac. At that point the attacker can move your files without us.
- The website in `site/` and the GitHub Pages build: static HTML, no forms, no
  accounts, nothing to authenticate.
- Missing hardening that crosses no boundary — the app is not sandboxed on
  purpose, because it manages a folder you choose.

## What the app does

Context for anyone reading the code with an eye for this.

- **It has no account, no server and no telemetry.** The only request it makes
  is a `GET` to `api.github.com` for the latest release, on the schedule you set
  under **Updates**, and the download that follows if you ask for it.
- **Nothing is deleted.** Removals go to the Trash (`FileManager.trashItem`),
  never `unlink`, so a setting you regret is a drag back out.
- **Nothing is overwritten.** A name collision counts up: `report.pdf`,
  `report-1.pdf`, `report-2.pdf`.
- **Preview mode** under **Filing** makes every destructive feature report what
  it would do without touching a file. It is the safe way to test a report.
- **An update is verified before it replaces the app.** The downloaded bundle
  has to carry the same bundle identifier, the version the release advertised, a
  Developer ID signature pinned to the running app's team, and Gatekeeper's own
  approval — a notarized build, so a revoked identity fails even if it was once
  valid.
- **It reads the quarantine attribute** that macOS writes on downloads, to know
  which site a file came from for routing rules. That value is used for matching
  and is never sent anywhere.
- **Releases are signed and notarized by Apple**, and both the zip and the disk
  image are stapled. The zip is what the updater and Homebrew fetch; the disk
  image is for a person. Anything you are offered from somewhere other than the
  releases page or the tap is not ours.
