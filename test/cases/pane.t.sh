#!/usr/bin/env bash
# End-to-end test for scripts/pane.sh — stubbed tmux and fzf, no live server.
# Proves the session ▸ window › pane tree (hierarchical MRU ordering, agent
# status glyphs, ANSI styling), the recorded pick, and the fzf plumbing
# (geometry via FZF_DEFAULT_OPTS, tree display flags and preview via argv).
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sep=$'\x1f'

stub_tmux
printf '%%1\n%%0\n%%2\n' > "$XDG_CACHE_HOME/tmux-fzf-pane-mru"   # %2 newest, %0 oldest, %3-%5 never used
stub_fzf_pick "$SANDBOX/fzf-dump" 4   # picks line 4: dev:2.3, pane %3

cd "$REPO_ROOT"
"$PWD/scripts/pane.sh" switch >/dev/null 2>&1

# fzf plumbing: tree display flags on argv, preview command as single argv
# elements; the preview WINDOW default rides the environment instead
assert_contains "ansi flag passed" "<--ansi>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "unit-separator delimiter passed" "--delimiter=" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "display restricted to field 2" "<--with-nth=2>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "header leads argv" "== ARGV
  <--header>
  <Select target pane.>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump" | sed '$d')"
assert_contains "preview command passed as argv" "
  <--preview>
  <$REPO_ROOT/scripts/.preview {}>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump" | sed '$d')"
grep -q '<--preview-window>' "$SANDBOX/fzf-dump" \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL window flag must not be on argv"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   no window flag on argv"; }

# fzf received the plugin geometry AND the follow default via the environment
assert_contains "geometry and follow via FZF_DEFAULT_OPTS" "ENV
  <--tmux center,62%,38% -m --preview-window :follow" "$(sed -n '/== ENV/,/== STDIN/p' "$SANDBOX/fzf-dump" | sed '$d')"

STDIN=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump" | sed 1d)

# Tree: targets of the displayed lines, in order. dev leads (its %2 is the
# most-recent pane); inside dev the windows follow pane recency (w2 %2, w0
# %0, w3 never-used); the current pane's window (w1) is hidden by default;
# ops trails. Single-pane windows merge into one line, ops w0 splits.
assert_eq "hierarchical MRU target order" \
"dev:2.2
dev:2.2
dev:2.0
dev:2.3
ops:0.1
ops:0.1
ops:0.1
ops:0.0
[cancel]" "$(printf '%s\n' "$STDIN" | cut -d"$sep" -f1)"

# Style: session lines bold with state counts, agent glyphs on agent panes,
# nothing on plain panes; merge marker on single-pane windows
assert_contains "session line bold with counts" "$(printf '\033[1m▸ dev\033[0m \033[1;33m⣽1\033[0m')" "$STDIN"
assert_contains "ops session shows its idle count" "$(printf '\033[1m▸ ops\033[0m \033[32m✓1\033[0m')" "$STDIN"
assert_contains "running agent pane carries spinner" "claude $(printf '\033[1;33m⣽\033[0m')" "$STDIN"
assert_contains "idle agent pane carries check" "claude $(printf '\033[32m✓\033[0m')" "$STDIN"
assert_contains "single-pane window merged with its pane" "$(printf '\033[2m ─ \033[0mhtop')" "$STDIN"
line=$(printf '%s\n' "$STDIN" | grep 'htop')
[[ "$line" != *"⣽"* && "$line" != *"✓"* ]] \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   non-agent pane has no state glyph"; } \
    || { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL non-agent pane got a state glyph"; }

# The pick (fzf returned line 4 = dev:2.3) was recorded as its pane_id
assert_eq "pick recorded" "%3" "$(tail -1 "$XDG_CACHE_HOME/tmux-fzf-pane-mru")"

# TMUX_FZF_MRU=0: plain list order (the list-panes row order), still a tree
stub_fzf_pick "$SANDBOX/fzf-dump-2"
rm -f "$XDG_CACHE_HOME/tmux-fzf-pane-mru"
TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
assert_eq "MRU=0 restores list order" \
"dev:2.0
dev:2.0
dev:2.2
dev:2.3
ops:0.1
ops:0.1
ops:0.1
ops:0.0
[cancel]" "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-2" | sed 1d | cut -d"$sep" -f1)"

# TMUX_FZF_SWITCH_CURRENT: the current pane re-enters by its own rank (w1 is
# the oldest ranked pane, so it lands after w0)
stub_fzf_pick "$SANDBOX/fzf-dump-3"
printf '%%1\n%%0\n%%2\n' > "$XDG_CACHE_HOME/tmux-fzf-pane-mru"
TMUX_FZF_SWITCH_CURRENT=1 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
assert_eq "SWITCH_CURRENT re-includes the current pane" \
"dev:2.2
dev:2.2
dev:2.0
dev:2.1
dev:2.3
ops:0.1
ops:0.1
ops:0.1
ops:0.0
[cancel]" "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-3" | sed 1d | cut -d"$sep" -f1)"

# tmux-agent-status sidecar: when its hook-written cache tracks a pane, the
# exact state replaces our capture inference. ask and parked never come from
# inference, so their glyphs prove the sidecar path; "done" on a pane whose
# captured output shows a spinner proves exactness beats heuristics.
# pane.sh reads $HOME/.cache/tmux-agent-status — point HOME at the sandbox and
# build the fixture at the path that resolution hits
TAS="$SANDBOX/.cache/tmux-agent-status"
mkdir -p "$TAS/panes" "$TAS/parked" "$TAS/wait"
stub_fzf_pick "$SANDBOX/fzf-dump-5"
printf 'ask\n' > "$TAS/panes/ops_%5.status"    # %5's capture has no spinner, but ask is exact
printf 'done\n' > "$TAS/panes/dev_%3.status"   # %3's capture shows a spinner - exact state wins
HOME="$SANDBOX" TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
STDIN5=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-5" | sed 1d)
assert_contains "sidecar ask state rendered" "claude $(printf '\033[1;31m❓\033[0m')" "$STDIN5"
assert_contains "ops session counts the ask" "$(printf '\033[1m▸ ops\033[0m \033[1;31m❓1\033[0m')" "$STDIN5"
line=$(printf '%s\n' "$STDIN5" | grep 'w3')
assert_contains "exact done beats spinner inference" "claude $(printf '\033[32m✓\033[0m')" "$line"
[[ "$line" != *"⣽"* ]] \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   spinner inference suppressed by exact state"; } \
    || { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL inference spinner leaked past sidecar"; }

# parked overrides everything, including a working status content
stub_fzf_pick "$SANDBOX/fzf-dump-6"
printf 'working\n' > "$TAS/panes/dev_%3.status"
: > "$TAS/parked/dev_%3.parked"
HOME="$SANDBOX" TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
line=$(printf '%s\n' "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-6" | sed 1d)" | grep 'w3')
assert_contains "parked file parks the pane" "claude $(printf '\033[2m⏸\033[0m')" "$line"

# timed wait: future expiry renders ⏳; expired wait is cleaned up like their
# reader does (file removed, wait content rewritten to done) and the pane
# falls back to the now-done status
stub_fzf_pick "$SANDBOX/fzf-dump-7"
rm -f "$TAS/parked/dev_%3.parked"
printf 'wait\n' > "$TAS/panes/dev_%3.status"
echo "$(( $(date +%s) + 600 ))" > "$TAS/wait/dev_%3.wait"
HOME="$SANDBOX" TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
line=$(printf '%s\n' "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-7" | sed 1d)" | grep 'w3')
assert_contains "future wait expiry renders hourglass" "claude $(printf '\033[36m⏳\033[0m')" "$line"
stub_fzf_pick "$SANDBOX/fzf-dump-8"
echo "$(( $(date +%s) - 10 ))" > "$TAS/wait/dev_%3.wait"
HOME="$SANDBOX" TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
[[ -f "$TAS/wait/dev_%3.wait" ]] \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL expired wait file not removed"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   expired wait file removed"; }
assert_eq "expired wait content rewritten to done" "done" "$(cat "$TAS/panes/dev_%3.status")"
line=$(printf '%s\n' "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-8" | sed 1d)" | grep 'w3')
assert_contains "expired wait falls back to done" "claude $(printf '\033[32m✓\033[0m')" "$line"
rm -rf "$TAS"

# kill keeps the flat "S:W.P: detail" list (with [current] shortcut)
stub_fzf_pick "$SANDBOX/fzf-dump-4"
"$PWD/scripts/pane.sh" kill >/dev/null 2>&1
assert_contains "kill uses the flat list" "dev:2.2: htop · ~/w2 [80x24]" \
    "$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-4")"

# .preview understands both line shapes: tree field 1 and flat "S:W.P: ..."
out=$("$PWD/scripts/.preview" "$(printf 'dev:2.2\037▸ dev')" 2>&1)
assert_eq "preview parses tree line" "CAPTURED:capture-pane -ep -t dev:2.2" "$out"
out=$("$PWD/scripts/.preview" "dev:2.2: htop · ~/w2" 2>&1)
assert_eq "preview parses flat line" "CAPTURED:capture-pane -ep -t dev:2.2" "$out"
out=$("$PWD/scripts/.preview" "$(printf '[cancel]\037[cancel]')" 2>&1)
assert_eq "preview skips cancel" "" "$out"

finish "pane.t.sh"
