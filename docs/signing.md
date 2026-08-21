# Signing and notarizing

An ad-hoc build — what `npm run build` produces — runs fine on the machine that
built it. To hand it to anyone else it needs to be signed with a **Developer ID
Application** certificate *and* notarized by Apple. Signing alone still trips
Gatekeeper.

Signing also keeps the granted Downloads permission stable across updates. An
ad-hoc signature changes on every rebuild, so macOS treats each build as a new
app and asks for access again.

## One-time setup

You need an Apple Developer account with a *Developer ID Application*
certificate in your keychain, and an
[app-specific password](https://support.apple.com/en-us/102654) for the notary
service. Store the credentials once:

```bash
xcrun notarytool store-credentials tideline \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

`tideline` is the profile name the build script looks for. Use another name and
pass it with `NOTARY_PROFILE=`.

## Per release

```bash
npm run notarize
```

That signs with the hardened runtime and a secure timestamp, uploads the zip,
waits for the ticket, staples it to the app, re-zips the stapled bundle, and
finishes with `spctl --assess` so you know Gatekeeper accepts it before you
publish it.

Stapling has to happen on the `.app` rather than the zip, which is why the
archive is rebuilt at the end — **ship the zip produced after that step**,
`app/dist/Tideline.zip`.

To sign without notarizing — a build for your own machines that survives a
rebuild — use `npm run sign`.

## Environment variables

| Variable | |
| --- | --- |
| `CODESIGN_IDENTITY` | The signing identity. Defaults to the first *Developer ID Application* in your keychain; `-` means ad-hoc |
| `NOTARY_PROFILE` | Stored `notarytool` profile name (default `tideline`) |
| `NOTARY_APPLE_ID` | Apple ID, instead of a stored profile |
| `NOTARY_TEAM_ID` | Team ID, instead of a stored profile |
| `NOTARY_PASSWORD` | App-specific password, instead of a stored profile |

The three `NOTARY_*` credentials exist for CI, which has no keychain profile to
read. Set all three and the build script uses them; otherwise it falls back to
the stored profile. See [Releasing](./releasing.md).

Calling the script by hand works the same way:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./app/build.sh --notarize
```

## When it fails

**"--notarize needs a Developer ID."** `CODESIGN_IDENTITY` is unset or ad-hoc.
Apple rejects ad-hoc signatures.

**`notarytool` returns `Invalid`.** Ask it what went wrong:

```bash
xcrun notarytool log <submission-id> --keychain-profile tideline
```

Usually a missing hardened runtime or timestamp — both of which `build.sh`
passes, so this normally means something re-signed the bundle afterwards.

**`spctl --assess` rejects the app.** The ticket did not staple. Check with
`xcrun stapler validate app/dist/Tideline.app`, and make sure you are shipping
the zip written *after* stapling rather than one from an earlier step.
