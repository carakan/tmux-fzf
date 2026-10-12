#!/usr/bin/env bash
# MRU bookkeeping for the tmux-fzf pickers.
#
#   mru.sh record <pane_id>   append a pane to the recency log (newest last)
#   mru.sh prune              drop dead panes, deduplicate, cap the log
#   mru.sh list               print the log, newest first
#   mru.sh file               print the log path (single source of it)
#
# Design: the log is append-only. "record" is a single append write, and one
# write(2) with O_APPEND is atomic on local filesystems, so concurrent
# recorders — both after-select-pane and after-select-window fire on one
# window switch — cannot corrupt the file or lose each other's entries. That
# removes the whole lock/tempfile/rewrite apparatus from the hot path: no
# flock (absent from stock macOS), no mktemp, nothing to clean up after a
# crash. Order lives in exactly one place: a reader walks the log front to
# back, so the last occurrence of a pane id is its recency rank.
#
# "prune" is the only writer that rewrites, and it runs once per picker open:
# keep the newest occurrence of each pane that still exists, capped, and
# replace the file atomically (temp file in the same directory + mv).
#
# Keyed by pane_id (%N): S:W.P indices shift when windows close, so an
# index-keyed entry would eventually point at a different pane.
#
# The log lives at ${XDG_CACHE_HOME:-~/.cache}/tmux-fzf-pane-mru, capped at
# 200 entries. TMUX_FZF_MRU=0 makes "record" a no-op, so the hooks from
# main.tmux can stay installed and the feature comes back on 1 without a
# reload.

mru_file="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-fzf-pane-mru"
mru_cap=200

case "${1:-}" in
    record)
        pid="${2:-}"
        [ -z "$pid" ] && exit 0
        [ "${TMUX_FZF_MRU:-1}" = "0" ] && exit 0
        d="${mru_file%/*}"
        [ -d "$d" ] || mkdir -p "$d"
        printf '%s\n' "$pid" >> "$mru_file"
        ;;
    prune)
        [ -f "$mru_file" ] || exit 0
        d="${mru_file%/*}"
        live="$(mktemp "$d/.tmux-fzf-mru-live.XXXXXX")"
        tmux list-panes -a -F '#{pane_id}' > "$live" 2>/dev/null || : > "$live"
        out="$(mktemp "$d/.tmux-fzf-mru.XXXXXX")"
        # Walk the log backwards: first hit is the newest occurrence, so
        # dedup and the cap both fall out of the walk. Output is restored to
        # file order (oldest first) for the readers.
        if awk -v cap="$mru_cap" '
            NR == FNR { ok[$0] = 1; next }
            { line[NR] = $0 }
            END {
                n = 0
                for (i = NR; i >= 1 && n < cap; i--)
                    if ((line[i] in ok) && !(line[i] in seen)) {
                        seen[line[i]] = 1
                        keep[++n] = line[i]
                    }
                for (i = n; i >= 1; i--) print keep[i]
            }' "$live" "$mru_file" > "$out"; then
            mv "$out" "$mru_file"
        else
            rm -f "$out"
        fi
        rm -f "$live"
        ;;
    list)
        [ -f "$mru_file" ] || exit 0
        # Effective order: deduplicated, newest first.
        awk '{ line[NR] = $0 } END { for (i = NR; i >= 1; i--) if (!seen[line[i]]++) print line[i] }' "$mru_file"
        ;;
    file)
        printf '%s\n' "$mru_file"
        ;;
    *)
        echo "usage: mru.sh record <pane_id> | prune | list | file" >&2
        exit 1
        ;;
esac
