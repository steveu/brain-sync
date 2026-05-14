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

See [`ops/README.md`](ops/README.md) for the full operational playbook.

## License

MIT — see [LICENSE](./LICENSE).
