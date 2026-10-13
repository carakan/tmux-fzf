#!/usr/bin/env bash
# Invariant of the FZF_DEFAULT_OPTS migration: user-facing fzf configuration
# must be data, never shell input. No picker may eval it, and the removed
# TMUX_FZF_OPTIONS / TMUX_FZF_BIN knobs must stay gone.
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

bad=$(grep -rn 'eval "\$TMUX_FZF_BIN\|\$TMUX_FZF_OPTIONS\|TMUX_FZF_BIN=' main.sh scripts/*.sh 2>/dev/null)
if [ -n "$bad" ]; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL removed knobs/eval resurfaced:"; echo "$bad" | sed 's/^/    /'
else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   no TMUX_FZF_OPTIONS/TMUX_FZF_BIN/eval of options"
fi

# every picker sources .envs (fzf options must reach the call sites)
for f in main.sh scripts/pane.sh scripts/window.sh scripts/session.sh scripts/menu.sh \
         scripts/clipboard.sh scripts/command.sh scripts/copy-mode.sh scripts/keybinding.sh scripts/process.sh; do
    if grep -q 'source .*\.envs' "$REPO_ROOT/$f"; then
        TESTS_PASS=$((TESTS_PASS+1))
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL $f does not source .envs"
    fi
done
echo "  ok   all pickers source .envs (grouped as one)"

# every fzf call expands the preview options as an array ([@]); a bare string
# expansion would need eval again
bad=$(grep -rn 'TMUX_FZF_PREVIEW_OPTIONS' main.sh scripts/*.sh | grep -v 'TMUX_FZF_PREVIEW_OPTIONS\[@\]' | grep -v '^scripts/.envs')
if [ -n "$bad" ]; then
    TESTS_FAIL=$((TESTS_FAIL+1)); echo "  FAIL preview options expanded as string:"; echo "$bad" | sed 's/^/    /'
else
    TESTS_PASS=$((TESTS_PASS+1)); echo "  ok   preview options always expanded as arrays"
fi

finish "no-eval invariant"
