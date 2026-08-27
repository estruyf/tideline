# Homebrew

`brew install --cask estruyf/tap/tideline` installs the same signed, notarized
zip the release page hands out, and puts `Tideline.app` in `/Applications`,
which is where the app expects to live.

The cask is [`homebrew/tideline.rb`](../homebrew/tideline.rb), and this repo is
where it is edited. [`homebrew/publish-cask.sh`](../homebrew/publish-cask.sh)
stamps it with a version and a checksum and copies it into the tap, so the tap
repository holds a generated file and nothing else — never edit it there, or the
next release will overwrite the change.

## What the cask says, and why

- **`auto_updates true`.** Tideline checks GitHub once a day and installs a new
  version itself. Telling Homebrew that stops `brew upgrade` from reinstalling
  over a copy the app may have already replaced. Someone who would rather
  Homebrew drove it runs `brew upgrade --greedy`, which works because the tap
  moves on every release either way.
- **`depends_on macos: ">= :sonoma"`.** `LSMinimumSystemVersion` is 14.0, and
  the in-app updater has no floor of its own — so for anyone still on macOS 13
  this line is the only thing between them and a bundle that will not launch.
  It has to move whenever the plist does.
- **`uninstall quit:`.** It is a background app with no Dock icon, so without
  this an upgrade would swap the bundle out from under a running copy.
- **`zap trash:`** names the same three paths as the app's own **Uninstall**
  sheet. None of them is in the Downloads folder: zapping Tideline removes
  Tideline, never anything Tideline filed.

## Setting up the tap, once

A tap is an ordinary public repository whose name starts with `homebrew-`.

```bash
gh repo create estruyf/homebrew-tap --public \
  --description "Homebrew casks for Elio Struyf's apps"
git clone https://github.com/estruyf/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
printf '# homebrew-tap\n\n```bash\nbrew install --cask estruyf/tap/tideline\n```\n' > README.md
git add . && git commit -m "init" && git push
```

The `Casks/` directory is what `brew` looks in, and `estruyf/tap` is how the
repository name is written once the `homebrew-` prefix is stripped.

Then seed it with the current release and check it installs:

```bash
HOMEBREW_TAP_TOKEN=<token> ./homebrew/publish-cask.sh --push
brew install --cask estruyf/tap/tideline
```

Finally, add `HOMEBREW_TAP_TOKEN` to this repository's Actions secrets: a
fine-grained personal access token, scoped to `estruyf/homebrew-tap` alone, with
**Contents: read and write**. The built-in `GITHUB_TOKEN` cannot be used — it
has no access to any repository but this one. Until the secret exists the
release workflow warns and carries on, so a missing token delays the tap rather
than failing a release.

## Every release after that

Nothing by hand. The release workflow hashes the zip it just notarized — the
exact bytes attached to the release, so it cannot race the CDN — stamps the
cask, and pushes it to the tap. Prereleases are skipped, because a cask carries
one version and it should be the one `releases/latest` returns.

If it is ever missed, or the secret was not there yet:

```bash
VERSION=1.9.0 HOMEBREW_TAP_TOKEN=<token> ./homebrew/publish-cask.sh --push
```

Without `--push` the script stamps the cask and prints it, which is the way to
see what would land. With no `ZIP=`, it downloads the release asset.

## Getting into homebrew-cask proper

`brew install --cask tideline`, with no tap, means a pull request to
[homebrew-cask](https://github.com/Homebrew/homebrew-cask). The token
`tideline` is unclaimed, and the cask here is written to their conventions, so
the file is ready. The repository is not yet:

| | Needed | `estruyf/tideline` as of 2026-08-27 |
| --- | --- | --- |
| Age | 30 days | 7 days |
| Stars | 75, **or** 30 forks, **or** 30 watchers | 8 stars, 0 forks, 0 watchers |

Those thresholds are in `brew audit --new`, which runs on every PR, so it fails
before a human reads it. And they **triple for a self-submission** — 225 stars,
90 forks or 90 watchers if Elio opens the PR himself. Someone else submitting it
faces the ordinary numbers.

So this is a later errand, not a blocked one. The tap is a complete install
story on its own; upstream mainly buys the shorter command. Check the current
numbers before spending a PR on it:

```bash
gh repo view estruyf/tideline --json stargazerCount,forkCount,watchers
```

When they clear, `brew bump-cask-pr` or a plain PR adding
`Casks/t/tideline.rb` is the whole job — and the tap stays where it is, since
people who already installed from it keep getting updates there.
