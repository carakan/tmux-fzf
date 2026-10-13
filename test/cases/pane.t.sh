#!/usr/bin/env bash
# End-to-end test for scripts/pane.sh switch — stubbed tmux and fzf, no live
# server. Proves the picker order, the recorded pick, and the exact option
# plumbing (geometry via FZF_DEFAULT_OPTS, headers/preview via argv).
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

stub_tmux
printf '%%1\n%%0\n%%2\n' > "$XDG_CACHE_HOME/tmux-fzf-pane-mru"   # %2 newest
stub_fzf_pick "$SANDBOX/fzf-dump"

cd "$REPO_ROOT"
"$PWD/scripts/pane.sh" switch >/dev/null 2>&1

# fzf received: the picker-specific preview command as single argv elements;
# the preview WINDOW default rides the environment instead
assert_contains "preview command passed as argv" "== ARGV
  <--header>
  <Select target pane.>
  <--preview>
  <$REPO_ROOT/scripts/.preview {}>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump" | sed '$d')"
grep -q '<--preview-window>' "$SANDBOX/fzf-dump" \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL window flag must not be on argv"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   no window flag on argv"; }

# fzf received the plugin geometry AND the follow default via the environment
assert_contains "geometry and follow via FZF_DEFAULT_OPTS" "ENV
  <--tmux center,62%,38% -m --preview-window :follow" "$(sed -n '/== ENV/,/== STDIN/p' "$SANDBOX/fzf-dump" | sed '$d')"

# picker order: MRU newest first, never-used last
assert_eq "MRU-newest pane first" "dev:2.2: [w2] htop" "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump" | sed 1d | head -1)"
assert_eq "never-used pane last" "dev:2.1: [w1] vim" "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump" | sed 1d | grep -v '^\[cancel\]$' | tail -1)"

# the pick (fzf returned line 1 = %2) was recorded
assert_eq "pick recorded" "%2" "$(tail -1 "$XDG_CACHE_HOME/tmux-fzf-pane-mru")"

# TMUX_FZF_MRU=0: plain index order, nothing recorded
stub_fzf_pick "$SANDBOX/fzf-dump-2"
rm -f "$XDG_CACHE_HOME/tmux-fzf-pane-mru"
TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
assert_eq "MRU=0 restores index order" "dev:2.1: [w1] vim" "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-2" | sed 1d | head -1)"
[ -f "$XDG_CACHE_HOME/tmux-fzf-pane-mru" ] \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL MRU=0 still recorded"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   MRU=0 records nothing"; }

finish "pane.sh switch"
