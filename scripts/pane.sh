#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

current_pane_origin=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#S:#{window_index}.#{pane_index}: #{window_name}')
current_pane=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#S:#{window_index}.#{pane_index}')

if [[ -z "$TMUX_FZF_PANE_FORMAT" ]]; then
    FMT="[#{window_name}:#{pane_title}] #{pane_current_command}  [#{pane_width}x#{pane_height}] [history #{history_size}/#{history_limit}, #{history_bytes} bytes] #{?pane_active,[active],[inactive]}#{?#{&&:#{pane_active},#{window_zoomed_flag}},[zoomed],}"
else
    FMT="$TMUX_FZF_PANE_FORMAT"
fi

# List panes once with their pane_id attached: the display lines keep the
# historical "S:W.P: label" shape (scripts/.preview strips at the first ": ")
# and the id lets the MRU ordering below key on pane_id — S:W.P indices shift
# when windows close and would point stale entries at the wrong pane.
sep=$'\x1f'
panes_raw=$(tmux list-panes -a -F "#{pane_id}${sep}#S:#{window_index}.#{pane_index}${sep}${FMT}")
panes=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" 'BEGIN { FS = sep } NF >= 3 { print $2 ": " $3 }')

# $TMUX_FZF_MRU — most-recently-used ordering (default on). Recording happens
# in the after-select-pane/after-select-window hooks from main.tmux, so it
# covers every switch, not only picks made here. TMUX_FZF_MRU=0 restores the
# plain index order.
panes_mru=""
if [ "${TMUX_FZF_MRU:-1}" != "0" ] && [ -x "$CURRENT_DIR/mru.sh" ]; then
    "$CURRENT_DIR/mru.sh" prune >/dev/null 2>&1 || true
    panes_mru=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" -v mru="$("$CURRENT_DIR/mru.sh" file)" '
        BEGIN {
            FS = sep
            # The log is oldest first, so the LAST entry is the most recent.
            # Collect it in file order — awk hash order is unspecified — then
            # rank the tail 1 upwards, so the ascending sort below puts the
            # most-recently-used pane on top. Duplicate entries in the log
            # are fine: the first hit is the newest and wins.
            while ((getline pid < mru) > 0)
                if (!(pid in seen)) { seen[pid] = 1; seq[++known] = pid }
            for (i = known; i >= 1; i--) rank[seq[i]] = known - i + 1
        }
        {
            key = ($1 in rank) ? rank[$1] : 1000000 + ++fresh
            printf "%d\t%s: %s\n", key, $2, $3
        }' | sort -k1,1n -s | cut -f2-)
fi

if [[ -z "$1" ]]; then
    action=$(printf "switch\nbreak\njoin\nswap\nlayout\nkill\nresize\n[cancel]" | fzf --header 'Select an action.')
else
    action="$1"
fi

[[ "$action" == "[cancel]" || -z "$action" ]] && exit
if [[ "$action" == "layout" ]]; then
    target_origin=$(printf "even-horizontal\neven-vertical\nmain-horizontal\nmain-vertical\ntiled\n[cancel]" | fzf --header 'Select a layout.')
    [[ "$target_origin" == "[cancel]" || -z "$target_origin" ]] && exit
    tmux select-layout "$target_origin"
elif [[ "$action" == "resize" ]]; then
    target_origin=$(printf "left\nright\nup\ndown\n[cancel]" | fzf --header 'Select direction.')
    [[ "$target_origin" == "[cancel]" || -z "$target_origin" ]] && exit
    if [[ "$target_origin" == "left" || "$target_origin" == "right" ]]; then
        size=$(printf "1\n2\n3\n5\n10\n20\n30\n[cancel]" | fzf --header 'Cells to be adjusted.')
        [[ "$size" == "[cancel]" || -z "$size" ]] && exit
        if [[ "$target_origin" == "left" ]]; then
            tmux resize-pane -L "$size"
        else
            tmux resize-pane -R "$size"
        fi
    elif [[ "$target_origin" == "up" || "$target_origin" == "down" ]]; then
        size=$(printf "1\n2\n3\n5\n10\n15\n20\n[cancel]" | fzf --header 'Lines to be adjusted.')
        [[ "$size" == "[cancel]" || -z "$size" ]] && exit
        if [[ "$target_origin" == "up" ]]; then
            tmux resize-pane -U "$size"
        else
            tmux resize-pane -D "$size"
        fi
    fi
else
    if [[ "$action" == "join" || "$action" == "kill" ]]; then
        fzf_header=(--header 'Select target pane(s). Press TAB to mark multiple items.')
    else
        fzf_header=(--header 'Select target pane.')
    fi
    if [[ "$action" == "switch" || "$action" == "join" ]]; then
        # MRU list leads when available; both are filtered the same way
        targets=${panes_mru:-$panes}
        if [[ -z "$TMUX_FZF_SWITCH_CURRENT" || "$action" == "join" ]]; then
            targets=$(echo "$targets" | grep -v "^$current_pane")
        fi
        target_origin=$(printf "%s\n[cancel]" "$targets" | fzf "${fzf_header[@]}" "${TMUX_FZF_PREVIEW_OPTIONS[@]}")
    else
        target_origin=$(printf "[current]\n%s\n[cancel]" "$panes" | fzf "${fzf_header[@]}" "${TMUX_FZF_PREVIEW_OPTIONS[@]}")
        target_origin=${target_origin/\[current\]/$current_pane_origin}
    fi
    [[ "$target_origin" == "[cancel]" || -z "$target_origin" ]] && exit
    target=$(echo "$target_origin" | sed 's/: .*//')
    if [[ "$action" == "switch" ]]; then
        zoom_active=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#{window_zoomed_flag}')
        echo "$target" | sed -E 's/:.*//g' | xargs -I{} tmux switch-client $TMUX_FZF_CLIENT_ARG -t {}
        echo "$target" | sed -E 's/\..*//g' | xargs -I{} tmux select-window -t {}
        echo "$target" | xargs -I{} tmux select-pane -t {}
        # Record the pick even when the hooks from main.tmux are not installed
        # (scripts invoked directly, e.g. a custom key binding). Recording is
        # an idempotent append, so a double call from both paths is harmless.
        # The id map is the same panes_raw listed above — no extra tmux call.
        if [ "${TMUX_FZF_MRU:-1}" != "0" ] && [ -x "$CURRENT_DIR/mru.sh" ]; then
            mru_id=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" -v r="$target" 'BEGIN { FS = sep } $2 == r { print $1 }')
            [ -n "$mru_id" ] && "$CURRENT_DIR/mru.sh" record "$mru_id" >/dev/null 2>&1
        fi
        if [[ "$zoom_active" == "1" ]]; then
            target_win=$(echo "$target" | sed -E 's/\..*//g')
            target_win_zoomed=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG -t "$target_win" '#{window_zoomed_flag}')
            if [[ "$target_win_zoomed" == "0" ]]; then
                tmux resize-pane -Z -t "$target"
            fi
        fi
    elif [[ "$action" == "kill" ]]; then
        echo "$target" | sort -r | xargs -I{} tmux kill-pane -t {}
    elif [[ "$action" == "swap" ]]; then
        panes=$(echo "$panes" | grep -v "^$target")
        target_swap_origin=$(printf "%s\n[cancel]" "$panes" | fzf --header 'Select another target pane.' "${TMUX_FZF_PREVIEW_OPTIONS[@]}")
        [[ "$target_swap_origin" == "[cancel]" || -z "$target_swap_origin" ]] && exit
        target_swap=$(echo "$target_swap_origin" | sed 's/: .*//')
        tmux swap-pane -s "$target" -t "$target_swap"
    elif [[ "$action" == "join" ]]; then
        echo "$target" | sort -r | xargs -I{} tmux move-pane -s {}
    elif [[ "$action" == "break" ]]; then
        cur_ses=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG | sed -e 's/^.//' -e 's/].*//')
        last_win_num=$(tmux list-windows | sort -nr | head -1 | sed 's/:.*//')
        ((last_win_num_after = last_win_num + 1))
        tmux break-pane -s "$target" -t "$cur_ses":"$last_win_num_after"
    fi
fi
