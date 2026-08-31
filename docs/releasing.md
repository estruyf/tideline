# Releasing

[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds,
signs, notarizes and staples on a macOS runner whenever a release is
**published**, then attaches both `Tideline-<version>-macos-universal.zip` and
`Tideline-<version>-macos-universal.dmg` to that release and keeps them as build
artifacts for 90 days.

The two are the same build for two different readers. The disk image is what a
person downloads: it opens onto the app, the Applications folder and an arrow
between them. The zip is what the app downloads when it updates itself, because
an update should be something it can unpack on its own rather than a volume it
has to mount. Homebrew reads the zip too — see [Homebrew](./homebrew.md).

Both are notarized, and each is stapled: the app's own ticket covers a copy
dragged out of the image, the image's covers a download that is checked before
it is ever opened. That is two round trips to Apple in one release, so the job
takes a few minutes longer than it used to.

## What the in-app updater expects

Every installed copy reads
`https://api.github.com/repos/estruyf/tideline/releases/latest` once a day, so a
release is also the thing that tells people an update exists. Three details of a
release matter to it:

- **The tag is the version.** `v1.3.0` is compared against the running
  `CFBundleShortVersionString`. A tag that does not parse as a version is
  ignored, and the workflow already refuses a tag that disagrees with
  `package.json`.
- **The zip is the asset, not the disk image.** The updater looks for
  `Tideline-<version>-macos-universal.zip` first, and falls back to any attached
  `.zip` with *tideline* in its name — the `.dmg` cannot match either test, on
  purpose. A release with no zip yet reports "no macOS build attached", which is
  what people see in the window between publishing and the workflow finishing.
  Renaming the zip is therefore a change to `Updater.macAsset`; renaming the
  disk image is not.
- **Signed and notarized, as the workflow already does.** The updater refuses to
  install a build that is not signed by the same team as the running copy, and
  refuses one Gatekeeper turns down. An unsigned or ad-hoc build attached to a
  release cannot be installed this way — it can only be downloaded by hand.

Drafts and pre-releases are skipped: `releases/latest` never returns them. The
workflow runs on **publish**, though, so for the few minutes between publishing
and the zip landing there is a real release with no build attached. A daily
check that lands in that window stays quiet and looks again later; someone
pressing **Check Now** is told the build is not up yet. Nothing is lost either
way, but it is a reason not to announce a release before the workflow is
green.

## Cutting a release

```bash
npm version patch        # bumps package.json, rebuilds, commits and tags
git push --follow-tags
gh release create v1.0.1 --generate-notes
```

Publishing the release triggers the workflow. The build refuses to start if the
tag and `package.json` disagree, so a mistagged release fails fast instead of
shipping a mislabelled bundle.

Before tagging, move the entries under `## [Unreleased]` in
[`CHANGELOG.md`](../CHANGELOG.md) into a section for the new version and update
the comparison links at the bottom.

## Running it by hand

`workflow_dispatch` runs the same job without a release. Give it a **tag** to
attach the result to an existing release — useful when a release build failed
halfway and you would rather repair it than cut a new version. Leave the tag
empty to only keep the build artifact.

## Repository secrets

**Settings → Secrets and variables → Actions**:

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application `.p12`, base64-encoded |
| `MACOS_CERTIFICATE_PWD` | Password you set when exporting the `.p12` |
| `APPLE_ID` | Apple ID email for the developer account |
| `APPLE_TEAM_ID` | Ten-character team ID |
| `APPLE_APP_PASSWORD` | App-specific password, not the Apple ID password |
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with **Contents: write** on `estruyf/homebrew-tap`, so a release can update the cask. Optional: without it the workflow warns and the tap is updated by hand — see [Homebrew](./homebrew.md) |

Export the certificate from **Keychain Access → My Certificates**, right-click
the *Developer ID Application* entry → *Export*, save as `.p12` with a password,
then encode it:

```bash
base64 -i Certificates.p12 | pbcopy
```

The workflow imports it into a throwaway keychain with a random per-run
password, builds, and removes the keychain again on the way out, whether the
build passed or failed.

## The Homebrew tap

The same job updates [`estruyf/homebrew-tap`](https://github.com/estruyf/homebrew-tap)
once the zip is attached, so `brew install --cask estruyf/tap/tideline` serves
the release within the same few minutes. It hashes the archive it just built
rather than downloading it back, and it skips prereleases. A missing
`HOMEBREW_TAP_TOKEN` is a warning, not a failure — the release still ships and
the tap is a `homebrew/publish-cask.sh --push` away.

[Homebrew](./homebrew.md) covers the cask itself, creating the tap the first
time, and what it would take to reach homebrew-cask proper.

## Release asset vs build artifact

The **release asset** is the download to hand to people: the app, zipped once.

The **Actions artifact** is a zip inside a zip, because GitHub wraps every
artifact in an archive of its own. It is named
`tideline-<version>-build`, deliberately different from the zip inside it —
naming both the same makes the download and its payload collide on disk, and
Archive Utility gives up with *"unsupported format"*.

## Checklist

- [ ] `CHANGELOG.md` has a section for the version, `[Unreleased]` is empty
- [ ] Screenshots retaken if the window changed, and the README points at the
      new `assets/<version>/` folder — `promo/scripts/capture.sh assets` takes
      the whole set, and `.claude/skills/screenshots/SKILL.md` is the procedure
- [ ] `npm version <patch|minor|major>` — this rebuilds, so it fails before
      committing if the build is broken
- [ ] `git push --follow-tags`
- [ ] `gh release create v<version> --generate-notes`
- [ ] Workflow green, and the zip is attached to the release
- [ ] The tap moved: `brew update && brew info --cask estruyf/tap/tideline`
      reports the new version
- [ ] Download the asset on another Mac and open it — Gatekeeper should not
      complain
- [ ] An older copy offers the update: **General › Updates › Check Now** on a
      previous version finds it, and **Update & Restart** comes back on the new
      one
