#!/usr/bin/env bash
# Shared helpers for the tmux-fzf test suite. Source from a case file:
#   . "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
#
# Every case runs in its own temp sandbox: PATH starts with a stub bin dir,
# XDG_CACHE_HOME points at the sandbox, and the environment is scrubbed of
# both the plugin's and fzf's variables, so nothing leaks in from a live
# tmux server (the test shell itself may well run inside one).

TESTS_PASS=0
TESTS_FAIL=0
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/tmux-fzf-test.XXXXXX")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB_BIN="$SANDBOX/bin"
export XDG_CACHE_HOME="$SANDBOX/cache"
mkdir -p "$STUB_BIN" "$XDG_CACHE_HOME"

# Scrub plugin, fzf and tmux-side variables the host shell may carry.
for _v in TMUX_FZF_OPTIONS TMUX_FZF_BIN TMUX_FZF_PANE_FORMAT TMUX_FZF_WINDOW_FORMAT \
          TMUX_FZF_SESSION_FORMAT TMUX_FZF_WINDOW_FILTER TMUX_FZF_PREVIEW \
          TMUX_FZF_PREVIEW_FOLLOW TMUX_FZF_CLIENT TMUX_FZF_CLIENT_WIDTH \
          TMUX_FZF_CLIENT_HEIGHT TMUX_FZF_MENU TMUX_FZF_SWITCH_CURRENT \
          TMUX_FZF_ORDER FZF_DEFAULT_OPTS; do
    unset "$_v"
done
unset _v
export PATH="$STUB_BIN:$PATH"

assert_eq() { # assert_eq <name> <expected> <actual>
    if [ "$2" == "$3" ]; then
        TESTS_PASS=$((TESTS_PASS + 1)); echo "  ok   $1"
    else
        TESTS_FAIL=$((TESTS_FAIL + 1))
        echo "  FAIL $1"; echo "    expected: $(printf '%q' "$2")"; echo "    actual:   $(printf '%q' "$3")"
    fi
}

assert_contains() { # assert_contains <name> <needle> <haystack>
    case "$3" in
        *"$2"*) TESTS_PASS=$((TESTS_PASS + 1)); echo "  ok   $1" ;;
        *) TESTS_FAIL=$((TESTS_FAIL + 1)); echo "  FAIL $1 (missing: $(printf '%q' "$2"))" ;;
    esac
}

stub_tmux() { # stub_tmux — panes for the pane picker (ids %0 %1 %2, panes dev:2.x)
    cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
sep=$'\x1f'
case "\$1" in
  -V) echo "tmux 3.5a" ;;
  display-message)
      if [[ "\$*" == *zoomed_flag* ]]; then echo 0
      else echo "dev:2.1: vim"; fi ;;
  list-panes)
      if [ "\$4" = '#{pane_id}' ]; then
          printf '%%0\n%%1\n%%2\n'
      else
          printf '%%1%sdev:2.1%s[w1] vim\n' "\$sep" "\$sep"
          printf '%%0%sdev:2.0%s[w0] zsh\n' "\$sep" "\$sep"
          printf '%%2%sdev:2.2%s[w2] htop\n' "\$sep" "\$sep"
      fi ;;
esac
exit 0
STUB
    chmod +x "$STUB_BIN/tmux"
}

# stub_fzf_pick <dumpfile> — fzf that logs argv, FZF_DEFAULT_OPTS and stdin,
# then picks the first line (the MRU-top entry for pane.sh switch).
stub_fzf_pick() {
    cat > "$STUB_BIN/fzf" <<STUB
#!/usr/bin/env bash
{
    echo "== ARGV"
    for a in "\$@"; do echo "  <\$a>"; done
    echo "== ENV"
    echo "  <\${FZF_DEFAULT_OPTS-UNSET}>"
    echo "== STDIN"
    cat
} > "$1"
head -1
STUB
    chmod +x "$STUB_BIN/fzf"
}

finish() { # finish <case-name> — report and clean the sandbox
    local name="$1"
    if [ "$TESTS_FAIL" -eq 0 ]; then
        echo "ok   $name ($TESTS_PASS checks)"
        rm -rf "$SANDBOX"
        exit 0
    fi
    echo "FAIL $name ($TESTS_FAIL of $((TESTS_PASS + TESTS_FAIL)) checks failed)"
    echo "  sandbox kept: $SANDBOX"
    exit 1
}
