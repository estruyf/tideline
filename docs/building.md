# Building Tideline

For running the app you do not need any of this — open the disk image from the
[latest release](https://github.com/estruyf/tideline/releases/latest). This page
is for building it on your own machine.

## Requirements

- macOS 14 or later
- Xcode, or the Command Line Tools (`xcode-select --install`)
- Swift 5.9 or later, which both of those bring along

There are no npm dependencies. `package.json` is a shortcut to
[`app/build.sh`](../app/build.sh), which you can call directly just as well.

## Build

```bash
npm run build            # universal binary into app/dist/
npm run build:install    # build, copy to /Applications, open it
```

The build produces a universal (Apple silicon + Intel) bundle, ad-hoc signed and
stamped with the version from `package.json`. Ad-hoc is fine on the machine that
built it; to hand the app to anyone else, see [Signing and notarizing](./signing.md).

## Scripts

| Script | |
| --- | --- |
| `npm run build` | Build into `app/dist/` |
| `npm run build:install` | Build, copy to `/Applications`, open it |
| `npm run build:zip` | Build and zip it for release |
| `npm run build:dmg` | Build and wrap it in `app/dist/Tideline.dmg` |
| `npm run dmg:background` | Re-render `assets/dmg/background.tiff` from its HTML source |
| `npm run dmg:layout` | Re-record the disk image's window layout — needs a real Finder, see [Releasing](./releasing.md) |
| `npm run sign` | Build signed with your Developer ID, then zip |
| `npm run notarize` | Sign, notarize with Apple, staple, zip |
| `npm run open` | Open the built app from `app/dist/` |
| `npm run quit` | Quit the running app |
| `npm run logs` | Follow the app's log |
| `npm run icon` | Redraw the app icon set and open it |
| `npm run clean` | Throw away build artefacts |
| `npm version patch` | Bump the version, rebuild, commit and tag |

`npm run sign` and `npm run notarize` pick the first *Developer ID Application*
identity out of your keychain; `CODESIGN_IDENTITY=` overrides it.

## Versioning

`package.json` is the single source of truth. `build.sh` reads the version from
it, so the bundle's `CFBundleShortVersionString` always matches:

```bash
npm version patch      # 1.0.0 -> 1.0.1, rebuilds, then commits and tags
```

The `version` lifecycle script rebuilds the app as part of the bump, so the
bundle in `app/dist/` matches the tag rather than lagging a release behind. A
failed build aborts the bump before anything is committed.

`CFBundleVersion` is a build timestamp, regenerated on every build. Override
either value for a one-off build with `VERSION=` or `BUILD_NUMBER=`:

```bash
VERSION=1.2.0-beta.1 npm run build
```

## Layout

| Path | |
| --- | --- |
| [`app/Package.swift`](../app/Package.swift) | SwiftPM manifest — one executable target, macOS 14+ |
| [`app/build.sh`](../app/build.sh) | Build, bundle, icon, sign, notarize, staple, zip, disk image |
| [`app/Tools/make-dmg-layout.sh`](../app/Tools/make-dmg-layout.sh) | Records the disk image's window layout into `app/Resources/dmg/DS_Store`, by hand, so the build never needs Finder |
| [`app/Resources/Info.plist`](../app/Resources/Info.plist) | Bundle template; `__VERSION__` and `__BUILD__` are substituted at build time |
| [`app/Tools/make-icon.swift`](../app/Tools/make-icon.swift) | Draws the icon set the build turns into `AppIcon.icns` |
| `app/Sources/Tideline/` | The app: `Organizer` files, `Cleaner` clears, `Controller` schedules, `Views/` is the window |
| `app/dist/` | Build output, ignored by git |

## Running it while developing

`swift run` starts the executable without a bundle, which means no bundle
identity — and no scoped Downloads permission. Build the app and run that
instead:

```bash
npm run build:install
npm run logs
```

The log at `~/Library/Logs/Tideline.log` is the fastest way to see what a sweep
did. Switch on *Preview mode* under **Filing** to watch it decide without
touching a file.

## Testing the first run

The first run is the part of the app a stranger sees and you never do: the
window opens on **Tideline is not filing yet**, macOS is not asked for the
Downloads folder until **Allow Access…** is pressed, and nothing is swept until
**Start Filing** is. Once you have answered it, that is answered for good — so
changing it means putting the app back to knowing nothing about you.

State lives in four places, and the permission macOS remembers is a fifth that
nothing in the app can clear:

```bash
# A running app rewrites its preferences on the way out, so quit it first.
# Not with a quit event: a sheet is modal, and the welcome sheet is exactly
# what is on screen when you are testing this — the app would stay up and
# quietly reopen with the settings it already had.
pkill -x Tideline; sleep 1

defaults delete be.eliostruyf.Tideline          # every setting
killall cfprefsd                                # the prefs daemon caches the domain
rm -rf "$HOME/Library/Application Support/Tideline"   # the activity history
rm -f  "$HOME/Library/Logs/Tideline.log"              # the log

# The Downloads permission. Nothing in the app can reset this one
tccutil reset SystemPolicyDownloadsFolder be.eliostruyf.Tideline

open -a Tideline
```

Two things survive that and can leave it looking like a first run when it is
not one:

- **The login item** is registered with macOS rather than stored in
  preferences, so deleting the domain leaves it switched on. Turn *Open at
  login* off before you reset, or take it out under **System Settings ›
  General › Login Items**.
- **`tccutil reset` clears the permission for every copy** of the app — the
  release build as well as the one you just built. The two carry different
  signatures, so granting it to one never granted it to the other anyway.

**General › Other › Uninstall…** does the same as the four commands above and
unregisters the login item with them, then quits and opens Finder on the app
without deleting it. Paired with the permission, that is the whole reset:

```bash
tccutil reset SystemPolicyDownloadsFolder be.eliostruyf.Tideline && open -a Tideline
```

To land in a particular state rather than the first one, write the two flags
that govern it — `hasGrantedAccess` is what decides whether the app reads the
folder at launch, and `hasStartedFiling` whether it files at all:

```bash
defaults write be.eliostruyf.Tideline hasGrantedAccess -bool false
defaults write be.eliostruyf.Tideline hasStartedFiling -bool false
```
