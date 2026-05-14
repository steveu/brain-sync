# brain-sync ops

Persistent-run setup for brain-sync on the Mac mini, via launchd.

## Layout

- `launchd/st.urm.brain-sync.plist` — the launchd job. Installed into `~/Library/LaunchAgents/`.
- The script itself lives in the repo at `bin/brain-sync`, with the orphan healer at `bin/heal-orphan`.
- Tests for `bin/heal-orphan` live at `tests/heal-orphan.bats`; run them from the repo root with `bats tests/` (requires `brew install bats-core`).

## Logs

- `~/Library/Logs/brain-sync.log` — script-level (one banner per run, then `git pull` / `unison` / commit-push outcomes)
- `~/Library/Logs/brain-sync.launchd.log` — launchd-level (process supervision, anything the script writes before redirecting stdout)

## Prerequisites

- Vault git repo at `~/brain` with a working `git push` to `github.com/steveu/brain`.
- Homebrew Unison at `/opt/homebrew/bin/unison`. Install with `brew install unison`.
- A Unison profile at `~/.unison/brain.prf` with roots `~/brain/vault` and the iCloud Brain folder. Out of scope for this repo — see ADR 0002 in `steveu/brain`.
- The iCloud Obsidian Brain folder at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain` already populated.

## One-time install

```sh
# 1. Drop the script into ~/code (or symlink — the plist hard-codes the path)
git clone https://github.com/steveu/brain-sync.git ~/code/brain-sync

# 2. Install the launchd plist
cp ~/code/brain-sync/ops/launchd/st.urm.brain-sync.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/st.urm.brain-sync.plist

# 3. Force a first run and verify
launchctl kickstart -k gui/$(id -u)/st.urm.brain-sync
tail -n 50 ~/Library/Logs/brain-sync.log
```

A clean cycle in the log looks like:

```
=== <timestamp> brain-sync starting ===
nothing new to commit
=== <timestamp> brain-sync done ===
```

## Reload after a script change

```sh
launchctl kickstart -k gui/$(id -u)/st.urm.brain-sync
```

The script is read fresh on each invocation; no rebuild step.

Note: `kickstart` is enough for script-only changes. Plist changes — including anything in the `WatchPaths` array — need a full `bootout` / `bootstrap` cycle (see "Replace the plist" below) before `launchd` picks up the new declarations.

## WatchPaths

The plist declares a `WatchPaths` array covering:

- `~/brain/vault`
- `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain`

Any create / delete / modify on the immediate contents of either directory triggers a run within ~5s. The 600s `StartInterval` heartbeat is kept as a safety net for missed events or daemon downtime.

### Smoke test

After a `bootout` / `bootstrap` cycle, verify `WatchPaths` is wired correctly:

```sh
touch ~/brain/vault/_watchpaths-smoke.md && rm ~/brain/vault/_watchpaths-smoke.md
sleep 6
tail -n 20 ~/Library/Logs/brain-sync.log
```

Within ~5s of the `touch`/`rm`, a new `=== <timestamp> brain-sync starting ===` banner should appear in the log.

## Disable temporarily

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/st.urm.brain-sync.plist
```

Re-enable with `bootstrap` again.

## Replace the plist

If the plist itself changes (interval, env, paths), bootout the old one before bootstrapping the new copy:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/st.urm.brain-sync.plist
cp ~/code/brain-sync/ops/launchd/st.urm.brain-sync.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/st.urm.brain-sync.plist
launchctl kickstart -k gui/$(id -u)/st.urm.brain-sync
```

## Troubleshooting

- `Operation not permitted` or `heal-orphan: unreadable:` lines in `~/Library/Logs/brain-sync.log` mean the launchd job is missing Full Disk Access. See the "Full Disk Access (macOS)" section in the top-level [README](../README.md).

## Reboot test

After install, reboot the Mac mini and confirm the job ran on its own:

```sh
tail -n 50 ~/Library/Logs/brain-sync.log
```

The most recent banner pair should sit within the last `StartInterval` (10 minutes) of boot.
