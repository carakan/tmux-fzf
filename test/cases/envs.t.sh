#!/usr/bin/env bash
# Tests for scripts/.envs — FZF_DEFAULT_OPTS construction and preview arrays.
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Desktop defaults: geometry + preview window prepended, user options last
# (fzf applies last occurrence wins, so the user's flags override the
# plugin's defaults).
out=$(bash -c '
    FZF_DEFAULT_OPTS="--no-bold"
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s\n%s" "$FZF_DEFAULT_OPTS" "$(printf "%s\n" "${TMUX_FZF_PREVIEW_OPTIONS[@]}")"')
assert_contains "desktop geometry prepended first" "--tmux center,62%,38% -m --preview-window :follow --no-bold" "$out"
assert_contains "preview window default in env" "--preview-window :follow" "$out"
assert_contains "preview command in options" "$REPO_ROOT/scripts/.preview {}" "$out"

# User --preview-window replaces the plugin's :follow default (later wins)
out=$(bash -c '
    FZF_DEFAULT_OPTS="--preview-window right:60%:wrap-word"
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s" "$FZF_DEFAULT_OPTS"')
assert_eq "user preview window comes after the default" \
    "--tmux center,62%,38% -m --preview-window :follow --preview-window right:60%:wrap-word" "$out"

# Compact client: near-fullscreen geometry + inline info, preview command off,
# and the chrome-strip APPENDED after the user's options so it wins there —
# padding and footer would eat the few lines a phone has.
out=$(bash -c '
    TMUX_FZF_CLIENT_WIDTH=100 TMUX_FZF_CLIENT_HEIGHT=20
    FZF_DEFAULT_OPTS="--padding=1,2 --footer=hi"
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s\narr:%d" "$FZF_DEFAULT_OPTS" "${#TMUX_FZF_PREVIEW_OPTIONS[@]}"')
assert_eq "compact strips padding and footer after user opts" \
    "--tmux center,96%,88% -m --info=inline --padding=1,2 --footer=hi --padding=0 --footer= --no-footer-border
arr:0" "$out"

# Wide-but-short client is compact too (height alone triggers)
out=$(bash -c '
    TMUX_FZF_CLIENT_WIDTH=400 TMUX_FZF_CLIENT_HEIGHT=15
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s" "$FZF_DEFAULT_OPTS"')
assert_contains "short client is compact" "--tmux center,96%,88%" "$out"

# Non-numeric geometry from an exotic client must not break anything
out=$(bash -c '
    TMUX_FZF_CLIENT_WIDTH=weird TMUX_FZF_CLIENT_HEIGHT=20
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s" "$FZF_DEFAULT_OPTS"')
assert_contains "non-numeric dimensions fall back to desktop" "--tmux center,62%,38%" "$out"

# TMUX_FZF_PREVIEW=0: preview command gone, no window default injected —
# your own FZF_DEFAULT_OPTS preview (if any) applies untouched
out=$(bash -c '
    TMUX_FZF_PREVIEW=0
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "arr:%d\n%s" "${#TMUX_FZF_PREVIEW_OPTIONS[@]}" "$FZF_DEFAULT_OPTS"')
assert_eq "preview off: empty arrays, no follow default" \
    "arr:0
--tmux center,62%,38% -m" "$out"

# Client pinning: TMUX_FZF_CLIENT_ARG
out=$(bash -c '
    TMUX_FZF_CLIENT=/dev/ttys004
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s" "$TMUX_FZF_CLIENT_ARG"')
assert_eq "client arg pins the client" "-c /dev/ttys004" "$out"

finish "envs"
