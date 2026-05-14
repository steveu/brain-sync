#!/usr/bin/env bats
# Tests for bin/heal-orphan. One test per row of the decision table in issue #2.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HELPER="$REPO_ROOT/bin/heal-orphan"
  TMP="$(mktemp -d)"
  export ICLOUD_ROOT="$TMP/icloud"
  export VAULT_REPO="$TMP/repo"
  VAULT="$VAULT_REPO/vault"
  mkdir -p "$ICLOUD_ROOT" "$VAULT"
  cd "$VAULT_REPO"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  # Seed an initial commit so HEAD exists for any merge-base lookups.
  echo "seed" > "$VAULT/seed.md"
  git add vault/seed.md
  git commit -q -m "seed"
}

teardown() {
  # Make sure nothing is left chmod 000 before we wipe the temp tree.
  if [[ -n "${TMP:-}" && -d "$TMP" ]]; then
    chmod -R u+rwX "$TMP" 2>/dev/null || true
    rm -rf "$TMP"
  fi
}

@test "row 1: vault missing, iCloud readable -> copy to vault, remove iCloud, exit 0" {
  mkdir -p "$ICLOUD_ROOT/notes"
  printf 'icloud body\n' > "$ICLOUD_ROOT/notes/a.md"

  run "$HELPER" "$ICLOUD_ROOT/notes/a.md" "$VAULT/notes/a.md"
  [ "$status" -eq 0 ]
  [ -f "$VAULT/notes/a.md" ]
  [ ! -e "$ICLOUD_ROOT/notes/a.md" ]
  run cat "$VAULT/notes/a.md"
  [ "$output" = "icloud body" ]
}

@test "row 2: vault and iCloud identical -> remove iCloud only, vault byte-identical, exit 0" {
  mkdir -p "$ICLOUD_ROOT/notes" "$VAULT/notes"
  printf 'same body\n' > "$VAULT/notes/b.md"
  cp "$VAULT/notes/b.md" "$ICLOUD_ROOT/notes/b.md"
  before_sum="$(shasum "$VAULT/notes/b.md" | awk '{print $1}')"

  run "$HELPER" "$ICLOUD_ROOT/notes/b.md" "$VAULT/notes/b.md"
  [ "$status" -eq 0 ]
  [ -f "$VAULT/notes/b.md" ]
  [ ! -e "$ICLOUD_ROOT/notes/b.md" ]
  after_sum="$(shasum "$VAULT/notes/b.md" | awk '{print $1}')"
  [ "$before_sum" = "$after_sum" ]
}

@test "row 3: vault and iCloud differ, clean 3-way merge -> merged vault, iCloud removed, exit 0" {
  mkdir -p "$ICLOUD_ROOT" "$VAULT"
  # Base in HEAD: three lines.
  printf 'line1\nline2\nline3\n' > "$VAULT/c.md"
  git add vault/c.md
  git commit -q -m "add c"
  # Vault edits line1, iCloud edits line3 — non-overlapping, clean merge.
  printf 'line1-vault\nline2\nline3\n' > "$VAULT/c.md"
  printf 'line1\nline2\nline3-icloud\n' > "$ICLOUD_ROOT/c.md"

  run "$HELPER" "$ICLOUD_ROOT/c.md" "$VAULT/c.md"
  [ "$status" -eq 0 ]
  [ ! -e "$ICLOUD_ROOT/c.md" ]
  run cat "$VAULT/c.md"
  [ "${lines[0]}" = "line1-vault" ]
  [ "${lines[1]}" = "line2" ]
  [ "${lines[2]}" = "line3-icloud" ]
}

@test "row 3 bonus: conflicting edits -> standard conflict markers, iCloud removed, exit 0" {
  mkdir -p "$ICLOUD_ROOT" "$VAULT"
  printf 'shared\n' > "$VAULT/d.md"
  git add vault/d.md
  git commit -q -m "add d"
  printf 'vault-change\n' > "$VAULT/d.md"
  printf 'icloud-change\n' > "$ICLOUD_ROOT/d.md"

  run "$HELPER" "$ICLOUD_ROOT/d.md" "$VAULT/d.md"
  [ "$status" -eq 0 ]
  [ ! -e "$ICLOUD_ROOT/d.md" ]
  grep -q '^<<<<<<<' "$VAULT/d.md"
  grep -q '^=======' "$VAULT/d.md"
  grep -q '^>>>>>>>' "$VAULT/d.md"
}

@test "row 3 new-file base: vault dirty, file not in HEAD -> merge against empty base, exit 0" {
  mkdir -p "$ICLOUD_ROOT" "$VAULT"
  # No commit for this file: HEAD lookup must fall back to empty base.
  printf 'vault-only\n' > "$VAULT/new.md"
  printf 'icloud-only\n' > "$ICLOUD_ROOT/new.md"

  run "$HELPER" "$ICLOUD_ROOT/new.md" "$VAULT/new.md"
  [ "$status" -eq 0 ]
  [ ! -e "$ICLOUD_ROOT/new.md" ]
  [ -f "$VAULT/new.md" ]
}

@test "row 4: iCloud unreadable -> both files untouched, exit 3, no .tmp debris" {
  mkdir -p "$ICLOUD_ROOT" "$VAULT"
  printf 'vault body\n' > "$VAULT/e.md"
  printf 'icloud body\n' > "$ICLOUD_ROOT/e.md"
  chmod 000 "$ICLOUD_ROOT/e.md"

  vault_before="$(shasum "$VAULT/e.md" | awk '{print $1}')"
  # We can't shasum the icloud file while it's 000, so capture size instead.
  icloud_size_before="$(stat -f %z "$ICLOUD_ROOT/e.md")"

  run "$HELPER" "$ICLOUD_ROOT/e.md" "$VAULT/e.md"
  [ "$status" -eq 3 ]

  vault_after="$(shasum "$VAULT/e.md" | awk '{print $1}')"
  icloud_size_after="$(stat -f %z "$ICLOUD_ROOT/e.md")"
  [ "$vault_before" = "$vault_after" ]
  [ "$icloud_size_before" = "$icloud_size_after" ]
  # No stray .tmp files anywhere in the vault tree.
  run find "$VAULT" -name '*.tmp'
  [ -z "$output" ]
}

@test "row 5: vault missing, iCloud already gone -> exit 0, no-op" {
  run "$HELPER" "$ICLOUD_ROOT/never.md" "$VAULT/never.md"
  [ "$status" -eq 0 ]
  [ ! -e "$VAULT/never.md" ]
  [ ! -e "$ICLOUD_ROOT/never.md" ]
}

@test "row 6: iCloud path outside iCloud root -> exit 4, no filesystem changes" {
  outside="$TMP/outside.md"
  printf 'outside body\n' > "$outside"
  outside_sum_before="$(shasum "$outside" | awk '{print $1}')"

  run "$HELPER" "$outside" "$VAULT/x.md"
  [ "$status" -eq 4 ]
  [ ! -e "$VAULT/x.md" ]
  outside_sum_after="$(shasum "$outside" | awk '{print $1}')"
  [ "$outside_sum_before" = "$outside_sum_after" ]
}
