#!/usr/bin/env bash
# Tests for scripts/.envs — FZF_DEFAULT_OPTS construction and preview arrays.
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Desktop defaults: geometry prepended, user options preserved after it
out=$(bash -c '
    FZF_DEFAULT_OPTS="--no-bold"
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s\n%s" "$FZF_DEFAULT_OPTS" "$(printf "%s\n" "${TMUX_FZF_PREVIEW_OPTIONS[@]}")"')
assert_contains "desktop geometry prepended" "--tmux center,62%,38% -m --no-bold" "$out"
assert_contains "preview command in options" "$REPO_ROOT/scripts/.preview {}" "$out"
assert_contains "preview follows" ":follow" "$out"

# Compact client: near-fullscreen geometry + inline info, preview off
out=$(bash -c '
    TMUX_FZF_CLIENT_WIDTH=100 TMUX_FZF_CLIENT_HEIGHT=20
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s\narr:%d" "$FZF_DEFAULT_OPTS" "${#TMUX_FZF_PREVIEW_OPTIONS[@]}"')
assert_contains "compact geometry" "--tmux center,96%,88% -m --info=inline --padding 1,0,0,0" "$out"
assert_contains "compact turns the preview off" "arr:0" "$out"

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

# TMUX_FZF_PREVIEW=0: preview arrays empty, everything else unchanged
out=$(bash -c '
    TMUX_FZF_PREVIEW=0
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "arr:%d\n%s" "${#TMUX_FZF_PREVIEW_OPTIONS[@]}" "${TMUX_FZF_PREVIEW_SESSION_OPTIONS[*]}"')
assert_eq "preview off empties the arrays" "arr:0" "$out"

# Client pinning: TMUX_FZF_CLIENT_ARG
out=$(bash -c '
    TMUX_FZF_CLIENT=/dev/ttys004
    source "'"$REPO_ROOT"'/scripts/.envs"
    printf "%s" "$TMUX_FZF_CLIENT_ARG"')
assert_eq "client arg pins the client" "-c /dev/ttys004" "$out"

finish "envs"
