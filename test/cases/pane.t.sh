#!/usr/bin/env bash
# End-to-end test for scripts/pane.sh — stubbed tmux and fzf, no live server.
# Proves the session ▸ window › pane tree (hierarchical MRU ordering, agent
# status glyphs, ANSI styling), the recorded pick, and the fzf plumbing
# (geometry via FZF_DEFAULT_OPTS, tree display flags and preview via argv).
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sep=$'\x1f'

stub_tmux
printf '%%1\n%%0\n%%2\n' > "$XDG_CACHE_HOME/tmux-fzf-pane-mru"   # %2 newest, %0 oldest, %3-%5 never used
stub_fzf_pick "$SANDBOX/fzf-dump" 5   # picks line 5: dev:2.3, pane %3

cd "$REPO_ROOT"
"$PWD/scripts/pane.sh" switch >/dev/null 2>&1

# fzf plumbing: tree display flags on argv, preview command as single argv
# elements; the preview WINDOW default rides the environment instead
assert_contains "ansi flag passed" "<--ansi>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "unit-separator delimiter passed" "--delimiter=" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "display restricted to field 2" "<--with-nth=2>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump")"
assert_contains "header leads argv" "== ARGV
  <--header>
  <Select target pane." "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump" | sed '$d')"
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
# %0, w1 the current pane's window, w3 never-used); ops trails. Single-pane
# windows merge into one line, ops w0 splits. The current pane is never a
# pick target, but its window still lists it read-only — here w1 holds only
# that pane, so the window line carries it inline. The agent pane's
# subprocess lines sit under its merged window line, keeping the pane as
# their target.
assert_eq "hierarchical MRU target order" \
"dev:2.2
dev:2.2
dev:2.0
dev:2.1
dev:2.3
dev:2.3
dev:2.3
dev:2.3
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

# Subprocesses of the agent pane, listed under it with status marks: sleeping
# (dim ·), running (▸), a zombie (✝); capped at three plus a count line. The
# non-agent zsh pane runs a child too — it must not be listed.
assert_contains "sleeping subprocess listed" "$(printf '\033[2m└\033[0m \033[2m·\033[0m \033[2mbash -c rg -n pattern src\033[0m')" "$STDIN"
assert_contains "running subprocess marked busy" "$(printf '\033[1;33m▸\033[0m \033[2mnode server.js\033[0m')" "$STDIN"
assert_contains "zombie subprocess marked dead" "$(printf '\033[2;31m✝\033[0m \033[2m(gzip)\033[0m')" "$STDIN"
assert_contains "subprocess list capped with count" "└ +4 subprocesses" "$STDIN"
child=$(printf '%s\n' "$STDIN" | grep 'node server.js' | head -1)
assert_eq "subprocess line targets its pane" "dev:2.3" "$(printf '%s' "$child" | cut -d"$sep" -f1)"
# %5's tmux command is node — the interpreter rule names the pane claude and
# still infers idle from its (empty-output) capture
line=$(printf '%s\n' "$STDIN" | grep 'ops-wt')
assert_contains "wrapper agent shown under its own name" "claude $(printf '\033[32m✓\033[0m')" "$line"
# state flags carry their own colors inside the dim detail: active ● bold
# green, zoomed 󰩨 bold magenta
line=$(printf '%s\n' "$STDIN" | grep 'w3')
assert_contains "active flag colored green" "$(printf '\033[1;32m●\033[0m')" "$line"
line=$(printf '%s\n' "$STDIN" | grep 'ops-wt')
assert_contains "zoomed flag colored magenta" "$(printf '\033[1;35m󰩨\033[0m')" "$line"

printf '%s\n' "$STDIN" | grep -q 'vim -O notes.md' \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL non-agent pane subprocess leaked"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   non-agent subprocess suppressed"; }
printf '%s\n' "$STDIN" | grep -q 'tail -f /var/log' \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL subprocess cap not applied"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   subprocesses beyond cap hidden"; }

# The pick (fzf returned line 4 = dev:2.3) was recorded as its pane_id
assert_eq "pick recorded" "%3" "$(tail -1 "$XDG_CACHE_HOME/tmux-fzf-pane-mru")"

# TMUX_FZF_MRU=0: plain list order (the list-panes row order), still a tree
stub_fzf_pick "$SANDBOX/fzf-dump-2"
rm -f "$XDG_CACHE_HOME/tmux-fzf-pane-mru"
TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
assert_eq "MRU=0 restores list order" \
"dev:2.1
dev:2.1
dev:2.0
dev:2.2
dev:2.3
dev:2.3
dev:2.3
dev:2.3
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
dev:2.3
dev:2.3
dev:2.3
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

# kill keeps the flat "S:W.P: detail" list (with [current] shortcut); the
# detail is styled like the tree — dim separator, agent name and state glyph
stub_fzf_pick "$SANDBOX/fzf-dump-4"
"$PWD/scripts/pane.sh" kill >/dev/null 2>&1
FLAT4=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-4")
assert_contains "kill uses the flat list" "dev:2.2: htop $(printf '\033[2m· ~/d/authservice [80x24]\033[0m')" "$FLAT4"
assert_contains "flat list names the wrapped agent" "dev:2.3: claude $(printf '\033[1;33m⣽\033[0m')" "$FLAT4"
assert_contains "flat list carries the idle state" "ops:0.1: claude $(printf '\033[32m✓\033[0m')" "$FLAT4"

# path styles: fish (default) shortens every directory but the last to one
# character; full keeps the path verbatim; basename keeps only the project dir
stub_fzf_pick "$SANDBOX/fzf-dump-9"
TMUX_FZF_PANE_PATH_STYLE=basename "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
line=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-9" | sed 1d | grep 'htop')
assert_contains "basename style keeps project dir" "htop $(printf '\033[2m· authservice [80x24]\033[0m')" "$line"
stub_fzf_pick "$SANDBOX/fzf-dump-10"
TMUX_FZF_PANE_PATH_STYLE=full "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
line=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-10" | sed 1d | grep 'htop')
assert_contains "full style keeps the verbatim path" "htop $(printf '\033[2m· ~/dev/authservice [80x24]\033[0m')" "$line"

# The current pane never becomes a pick row, but its window shows it
# read-only. When the current pane shares a window with other panes, the
# window line carries it (green ● + command + state) next to the window name.
stub_tmux
export STUB_CURRENT="ops:0.0"
stub_fzf_pick "$SANDBOX/fzf-dump-11"
TMUX_FZF_MRU=0 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
STDIN11=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-11" | sed 1d)
line=$(printf '%s\n' "$STDIN11" | grep 'zsh' | grep '●' | head -1)
assert_contains "current pane annotated on its window line" "$(printf '\033[1;32m●\033[0m \033[2mzsh\033[0m')" "$line"
printf '%s\n' "$STDIN11" | cut -d"$sep" -f1 | grep -qx "ops:0.0" \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL current pane became a pick target"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   current pane stays out of the pick list"; }
unset STUB_CURRENT
stub_tmux

# Glyph legend: the tree header explains only the states on screen, and the
# cancel row reads as an action (styled field 2, clean target field 1)
stub_fzf_pick "$SANDBOX/fzf-dump-12"
"$PWD/scripts/pane.sh" switch >/dev/null 2>&1
ARGV12=$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump-12" | sed '$d')
assert_contains "legend explains the running glyph" "$(printf '\033[1;33m⣽\033[0m busy')" "$ARGV12"
assert_contains "legend explains the idle glyph" "$(printf '\033[32m✓\033[0m done')" "$ARGV12"
assert_contains "legend marks the current pane" "$(printf '\033[1;32m●\033[0m current')" "$ARGV12"
assert_contains "legend marks zoomed windows" "$(printf '\033[1;35m󰩨\033[0m zoomed')" "$ARGV12"
STDIN12=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-12" | sed 1d)
assert_contains "cancel row renders as an action" "$sep$(printf '\033[2;3m[cancel]\033[0m')" "$STDIN12"
printf '%s\n' "$STDIN12" | cut -d"$sep" -f1 | grep -qx "\[cancel\]" \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   cancel target stays clean"; } \
    || { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL cancel target carries styling"; }

# Agent behind a shell: the pane root is the shell, claude is its child. The
# pane still reads "claude", and the subprocess list starts at the agent —
# claude itself is not repeated — with one indent step per level.
cat > "$STUB_BIN/ps" <<'PSTUB'
#!/usr/bin/env bash
printf '  5014  4801 S zsh\n'
printf '  5015  5014 S env DEBUG=1 node /usr/local/bin/claude --resume\n'
printf '  5021  5015 S bash -c rg -n pattern src\n'
printf '  5022  5021 S rg -n pattern src\n'
printf '    1     0 S /sbin/launchd\n'
PSTUB
chmod +x "$STUB_BIN/ps"
stub_fzf_pick "$SANDBOX/fzf-dump-13"
"$PWD/scripts/pane.sh" switch >/dev/null 2>&1
STDIN13=$(sed -n '/== STDIN/,$p' "$SANDBOX/fzf-dump-13" | sed 1d | sed 's/\x1b\[[0-9;]*m//g')
printf '%s\n' "$STDIN13" | grep -q 'omp --continue\|claude --resume' \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL agent repeated as its own subprocess"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   agent not repeated as its own subprocess"; }
assert_contains "subtree rooted at the agent" "└ · bash -c rg -n pattern src" "$STDIN13"
assert_contains "grandchild indented one step deeper" "├" "$STDIN13"
printf '%s\n' "$STDIN13" | grep -q '^dev:2.3.*      └ · bash' && printf '%s\n' "$STDIN13" | grep -q '        └ · rg -n pattern' \
    && { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   subprocess indent steps by depth"; } \
    || { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL subprocess depth indent"; }
stub_tmux

# Popup sizing: the tree asks for a height that fits its lines, but only when
# the user has not pinned a geometry and the compact layout is not in charge.
stub_fzf_pick "$SANDBOX/fzf-dump-14"
TMUX_FZF_CLIENT_HEIGHT=40 TMUX_FZF_CLIENT_WIDTH=200 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
assert_contains "tree popup sized to the tree" "<--tmux>" "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump-14")"
assert_contains "tree popup keeps the desktop width" "center,62%," "$(sed -n '/== ARGV/,/== ENV/p' "$SANDBOX/fzf-dump-14")"
stub_fzf_pick "$SANDBOX/fzf-dump-15"
FZF_DEFAULT_OPTS="--tmux center,80%,50%" TMUX_FZF_CLIENT_HEIGHT=40 TMUX_FZF_CLIENT_WIDTH=200 \
    "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
grep -q '<--tmux>' "$SANDBOX/fzf-dump-15" \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL pinned popup geometry overridden"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   pinned popup geometry wins"; }
stub_fzf_pick "$SANDBOX/fzf-dump-16"
TMUX_FZF_CLIENT_HEIGHT=20 TMUX_FZF_CLIENT_WIDTH=80 "$PWD/scripts/pane.sh" switch >/dev/null 2>&1
grep -q '<--tmux>' "$SANDBOX/fzf-dump-16" \
    && { TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL compact layout got tree sizing"; } \
    || { TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   compact layout owns the geometry"; }

# .preview understands both line shapes: tree field 1 and flat "S:W.P: ..."
out=$("$PWD/scripts/.preview" "$(printf 'dev:2.2\037▸ dev')" 2>&1)
assert_eq "preview parses tree line" "CAPTURED:capture-pane -ep -t dev:2.2" "$out"
out=$("$PWD/scripts/.preview" "dev:2.2: htop · ~/w2" 2>&1)
assert_eq "preview parses flat line" "CAPTURED:capture-pane -ep -t dev:2.2" "$out"
out=$("$PWD/scripts/.preview" "$(printf '[cancel]\037[cancel]')" 2>&1)
assert_eq "preview skips cancel" "" "$out"

finish "pane.t.sh"
