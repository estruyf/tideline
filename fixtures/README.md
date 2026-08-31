# Shared fixtures

Cases both apps are expected to agree on. Each one pins a moment, a set of
settings and a folder listing, and states what a sweep would move.

The two implementations do not share a build, so this is what keeps them in
step. `sweep-cases.json` is the contract; `docs/behaviour.md` is the prose.

- **Windows** runs them in [`windows/src-tauri/crates/tideline-core/tests/fixtures.rs`](../windows/src-tauri/crates/tideline-core/tests/fixtures.rs)
  via `cargo test`.
- **macOS** does not run them yet — the Swift planner reads the filesystem
  directly rather than taking a list of entries, so it needs the same
  pure/IO split the Rust side has before it can. Until then this file is the
  Windows app's spec and the macOS app's to-do.

A case marked `"pending": true` describes behaviour neither engine implements
yet — the routing rules in `docs/behaviour.md` are written down here before they
are written in code. Runners skip those, so the suite stays green; deleting the
flag is what turns a case into a failing test and puts it on the to-do list.

Timestamps are naive local times on purpose. `now` and every `stamp` shift
together with the machine's zone, so a case means the same thing in Brussels as
in Auckland — which is also how the app behaves, since it files by local day.
