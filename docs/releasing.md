# Releasing

[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds,
signs, notarizes and staples on a macOS runner whenever a release is
**published**, then attaches `Tideline-<version>-macos-universal.zip` to that
release and keeps it as a build artifact for 90 days.

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

Export the certificate from **Keychain Access → My Certificates**, right-click
the *Developer ID Application* entry → *Export*, save as `.p12` with a password,
then encode it:

```bash
base64 -i Certificates.p12 | pbcopy
```

The workflow imports it into a throwaway keychain with a random per-run
password, builds, and removes the keychain again on the way out, whether the
build passed or failed.

## Release asset vs build artifact

The **release asset** is the download to hand to people: the app, zipped once.

The **Actions artifact** is a zip inside a zip, because GitHub wraps every
artifact in an archive of its own. It is named
`tideline-<version>-build`, deliberately different from the zip inside it —
naming both the same makes the download and its payload collide on disk, and
Archive Utility gives up with *"unsupported format"*.

## Checklist

- [ ] `CHANGELOG.md` has a section for the version, `[Unreleased]` is empty
- [ ] Screenshot in `assets/` refreshed if the window changed, and the README
      points at the new file
- [ ] `npm version <patch|minor|major>` — this rebuilds, so it fails before
      committing if the build is broken
- [ ] `git push --follow-tags`
- [ ] `gh release create v<version> --generate-notes`
- [ ] Workflow green, and the zip is attached to the release
- [ ] Download the asset on another Mac and open it — Gatekeeper should not
      complain
