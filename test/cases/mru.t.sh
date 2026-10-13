#!/usr/bin/env bash
# Unit tests for scripts/mru.sh — the append-only recency log.
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

MRU="$REPO_ROOT/scripts/mru.sh"
FILE="$XDG_CACHE_HOME/tmux-fzf-pane-mru"

# record appends; list shows the effective order (dedup, newest first)
"$MRU" record %1; "$MRU" record %2; "$MRU" record %1
assert_eq "list is deduped, newest first" $'%1\n%2' "$("$MRU" list)"

# TMUX_FZF_MRU=0 makes record a no-op
TMUX_FZF_MRU=0 "$MRU" record %9
assert_eq "MRU=0 stops recording" $'%1\n%2' "$("$MRU" list)"

# concurrent records: a single atomic append each, none may be lost
for i in $(seq 24); do "$MRU" record "%$((i % 6))" & done; wait
n=$(wc -l < "$FILE" | tr -d ' ')
assert_eq "24 concurrent appends all landed" "27" "$n"

# prune keeps exactly the live panes, deduped; exact order is racy here
stub_tmux
"$MRU" prune
assert_eq "prune keeps the live set" $'%0\n%1\n%2' "$(cat "$FILE" | sort)"
assert_eq "prune dedupes to one line per pane" "3" "$(wc -l < "$FILE" | tr -d ' ')"

# cap: append 250 more live ids; prune keeps the newest 200
for i in $(seq 250); do printf '%%x%03d\n' "$i" >> "$FILE"; done
cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "list-panes -a") { printf '%%0\n%%1\n%%2\n'; for i in $(seq 51 250); do printf '%%x%03d\n' "$i"; done; } ;;
esac
exit 0
STUB
chmod +x "$STUB_BIN/tmux"
"$MRU" prune
assert_eq "cap 200" "200" "$(wc -l < "$FILE" | tr -d ' ')"
assert_eq "cap keeps the newest" "%x250" "$(tail -1 "$FILE")"
assert_eq "cap drops the oldest" "0" "$(grep -c '^%x0[0-4][0-9]$' "$FILE" || true)"

# picker ordering with the exact awk block pane.sh uses: newest first, then never-used
rm -f "$FILE"; "$MRU" record %1; "$MRU" record %2; "$MRU" record %0   # newest = %0
sep=$'\037'
panes_raw="%1${sep}dev:2.1${sep}vim
%0${sep}dev:2.0${sep}zsh
%2${sep}dev:2.2${sep}htop
%9${sep}dev:2.9${sep}never used"
"$MRU" prune >/dev/null   # picker-open prune, as pane.sh does
panes_mru=$(printf '%s\n' "$panes_raw" | awk -v mru="$("$MRU" file)" '
    BEGIN {
        FS = "\037"
        while ((getline pid < mru) > 0)
            if (!(pid in seen)) { seen[pid] = 1; seq[++known] = pid }
        for (i = known; i >= 1; i--) rank[seq[i]] = known - i + 1
    }
    {
        key = ($1 in rank) ? rank[$1] : 1000000 + ++fresh
        printf "%d\t%s: %s\n", key, $2, $3
    }' | sort -k1,1n -s | cut -f2-)
assert_eq "picker order: MRU newest first, never-used last" \
$'dev:2.0: zsh\ndev:2.2: htop\ndev:2.1: vim\ndev:2.9: never used' "$panes_mru"

# missing-file edge cases
rm -f "$FILE"
assert_eq "list on missing file is empty" "" "$("$MRU" list)"
"$MRU" prune
if [ -f "$FILE" ]; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL prune must not recreate a missing file"
else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   prune on missing file is a no-op"
fi

# no flock/tac outside comments (portability: stock macOS has neither)
if grep -vE '^[[:space:]]*#' "$MRU" | grep -Eq '\bflock\b|\btac\b'; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL mru.sh must not call flock/tac"
else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   no flock/tac in code"
fi

finish "mru.sh"
