#!/usr/bin/env bash
# Seeds the settings the newer panes need before a screenshot run.
#
# `tideline-demo-files.sh` fills a folder; this fills the two panes that would
# otherwise be shot empty. A routing rule can be written straight into
# UserDefaults because it is only JSON. A place cannot: it holds a security
# bookmark, which only the app can mint — so that one is two clicks by hand,
# printed at the end.
#
# Snapshot your real settings first:
#   defaults export be.eliostruyf.Tideline /tmp/tideline.plist
set -euo pipefail

domain="be.eliostruyf.Tideline"
archive="$HOME/Downloads-demo-archive"

read -r -d '' rules <<'JSON' || true
[{"id":"demo-invoices","name":"Invoices","isEnabled":true,"tests":[
{"id":"6C6E1B94-0000-4000-A000-000000000001","field":"name","pattern":"*invoice*","matchCase":false},
{"id":"6C6E1B94-0000-4000-A000-000000000002","field":"where_from","pattern":"*stripe*","matchCase":false}]}]
JSON

hex="$(printf '%s' "$rules" | xxd -p | tr -d '\n')"
defaults write "$domain" rules -data "$hex"

mkdir -p "$archive/2026/kwartaal 3/in"

cat <<TXT

Seeded:
  • routing rule "Invoices" — name *invoice*, downloaded from *stripe*
  • $archive/2026/kwartaal 3/in

Two things the shell cannot do, because a saved place holds a macOS bookmark:

  1. Move out › Add a place… → pick  $archive
     name it  2026 · bookkeeping   and set Inside to  {yyyy}/kwartaal {q}/in
  2. Move out › New search… → "A rule I wrote" → Invoices → Move
     so the Moved out list has a batch in it with a Put Back beside it.

Then restart Tideline so it reads the rule, and capture.
TXT
