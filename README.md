# brain-sync

A small bash script + launchd job that keeps a single Mac mini in the middle of a three-way Obsidian vault sync: `git pull --rebase` from `github.com/steveu/brain`, `unison brain` against the iCloud Obsidian folder that iOS reads, then commit and push anything new the iCloud side dropped in. Driven by a 10-minute LaunchAgent, designed to be invisible while the Mac is awake.

The architecture (why Unison, why a separate iCloud copy, what the trade-offs are) is recorded in [ADR 0002 in `steveu/brain`](https://github.com/steveu/brain/blob/main/docs/adr/0002-vault-sync-via-unison.md). This repo is just the moving parts.

## What's in here

- `bin/brain-sync` — the sync script (`set -euo pipefail`).
- `bin/heal-orphan` — single-orphan healer invoked by `brain-sync` when unison stalls on a FileProvider deadlock.
- `tests/` — bats-core tests for `heal-orphan`. Run with `bats tests/`.
- `ops/launchd/st.urm.brain-sync.plist` — the LaunchAgent, runs every 600s.
- `ops/README.md` — install / reload / disable / logs.

## Install on a fresh Mac mini

```sh
# 1. Prerequisites
brew install unison git bats-core
# bats-core is only needed to run the test suite; the sync itself needs unison + git.
# Vault and Unison profile setup are out of scope — see ADR 0002.

# 2. Clone this repo to ~/code
git clone https://github.com/steveu/brain-sync.git ~/code/brain-sync

# 3. Install the LaunchAgent
cp ~/code/brain-sync/ops/launchd/st.urm.brain-sync.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/st.urm.brain-sync.plist

# 4. Verify
launchctl kickstart -k gui/$(id -u)/st.urm.brain-sync
tail -n 20 ~/Library/Logs/brain-sync.log
```

The plist also declares `WatchPaths` on `~/brain/vault` and the iCloud Brain folder, so any write under either tree triggers a sync within ~5s in addition to the 10-minute heartbeat. The `StartInterval` heartbeat is retained as a safety net for missed events or daemon downtime.

See [`ops/README.md`](ops/README.md) for the full operational playbook, including the `WatchPaths` smoke test.

## Full Disk Access (macOS)

The launchd job needs Full Disk Access (FDA) to read files in `~/Library/Mobile Documents/iCloud~md~obsidian/...`. An interactive shell inherits Terminal's FDA grant; a launchd-spawned process does not. macOS's TCC is per-executable and per-calling-app, so the same `cat` that succeeds when you run `bin/brain-sync` by hand will fail when launchd runs it.

### Symptom

In `~/Library/Logs/brain-sync.log`, look for either of:

```
cat: /Users/<you>/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain/<...>.md: Operation not permitted
heal-orphan: unreadable: <path> — likely needs Full Disk Access for the caller (see issue #4)
```

The first line is the raw failure from `cat`. The second is `bin/heal-orphan` wrapping that failure with a hint and exiting `3`. Either means FDA is missing on the launchd side.

### Fix

1. Open System Settings → Privacy & Security → Full Disk Access.
2. Add `/bin/bash`. (You'll need to unlock and use the `+` button; `/bin` is hidden by default, so press Cmd-Shift-G in the file picker and paste `/bin/bash`.) `bin/brain-sync` shebangs to `#!/bin/bash` and launchd invokes that interpreter directly, so granting `/bin/bash` covers the whole job tree. Narrower would be adding `bin/brain-sync` itself, but TCC keys on the actual executable doing the read, which is `bash`.
3. Bounce the job so it picks up the new grant:

   ```sh
   launchctl kickstart -k gui/$(id -u)/st.urm.brain-sync
   ```

### Verify

```sh
tail -n 50 ~/Library/Logs/brain-sync.log
```

A healthy log after the bounce has no `Operation not permitted` and no `heal-orphan: unreadable:` lines.

## License

MIT — see [LICENSE](./LICENSE).
