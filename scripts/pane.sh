#!/usr/bin/env bash
# Pane picker. switch/join get a session ▸ window › pane tree with per-pane
# agent status; kill/swap/break/resize keep the flat target list.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

current_pane=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#S:#{window_index}.#{pane_index}')
current_pane_origin=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#S:#{window_index}.#{pane_index}: #{window_name}')

sep=$'\x1f'
if [[ -z "$TMUX_FZF_PANE_FORMAT" ]]; then
    # command first — the tree uses it as the pane's name slot and strips the
    # "cmd · " prefix from the detail; the dim tail is the working directory's
    # basename (the worktree or project name) plus the state flags. TMUX_FZF_
    # PANE_FORMAT replaces this detail wholesale (tree, status glyph and
    # preview still wrap it).
    FMT='#{pane_current_command} · #{b:pane_current_path}#{?pane_active, ●,}#{?window_zoomed_flag, ⤢,}'
else
    FMT="$TMUX_FZF_PANE_FORMAT"
fi

# One list-panes pass carries everything the tree needs: pane_id (stable MRU
# key — S:W.P indices shift when windows close), the S:W.P target, session,
# window index, window name, current command, dead flag and the display
# detail.
panes_raw=$(tmux list-panes -a -F "#{pane_id}${sep}#S:#{window_index}.#{pane_index}${sep}#S${sep}#{window_index}${sep}#{window_name}${sep}#{pane_current_command}${sep}#{pane_dead}${sep}${FMT}")

# Flat targets for the structural actions — the same "S:W.P: detail" shape
# .preview and the sed-based handlers already parse.
panes=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" 'BEGIN { FS = sep } NF >= 8 { print $2 ": " $8 }')

# Agent status, inferred at picker-open time from the pane itself — no daemon,
# no hooks: a pane whose current command is a known coding agent gets its last
# output lines inspected; a spinner or "esc to interrupt" means running,
# anything else means the agent sits idle (turn done, waiting for you). Dead
# panes — any pane, agent or not — come straight from tmux's dead flag.
agent_re='claude|codex|gemini|aider|copilot|cursor-agent|opencode|crush|amp|qwen|droid|omp'
statuses=""
while IFS="$sep" read -r pid _ptarget _psess _pwin _pwinname pcmd pdead _pdetail; do
    state=""
    if [[ "$pdead" == "1" ]]; then
        state=dead
    elif [[ "$pcmd" =~ ^($agent_re)$ ]]; then
        if tmux capture-pane -p -t "$pid" -S -5 2>/dev/null |
            grep -qE '⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|⣾|⣽|⣻|⣿|⣯|⣷|⣟|esc to interrupt|✢|✳|✶|✻|✽|✦|Thinking'; then
            state=running
        else
            state=idle
        fi
    fi
    [ -n "$state" ] && statuses+="${pid}${sep}${state}"$'\n'
done <<< "$panes_raw"

mru_file=""
if [ "${TMUX_FZF_MRU:-1}" != "0" ] && [ -x "$CURRENT_DIR/mru.sh" ]; then
    "$CURRENT_DIR/mru.sh" prune >/dev/null 2>&1 || true
    mru_file="$("$CURRENT_DIR/mru.sh" file)"
fi

# Session ▸ window › pane tree. Ordering is hierarchical MRU: the most
# recently used pane pulls its window to the top of its session and pulls its
# session to the top of the list; inside a group, index order rules.
# TMUX_FZF_MRU=0 degrades to plain list order everywhere. A window with a
# single pane collapses into one line; several panes list under their window.
# Every line carries its jump target as field 1 and shows field 2 only
# (--with-nth), so tree decoration and ANSI styling never leak into the
# switch handlers or the preview — the pick handler reads field 1, the
# preview captures field 1.
export pane_statuses="$statuses"
tree=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" \
    -v mru_file="$mru_file" \
    -v excl_current=$([[ -z "$TMUX_FZF_SWITCH_CURRENT" ]] && echo 1 || echo 0) \
    -v cur="$current_pane" '
    BEGIN {
        FS = sep
        ESC = sprintf("%c", 27)
        bold = ESC "[1m"; ital = ESC "[3m"; dim = ESC "[2m"; rst = ESC "[0m"
        run_c = ESC "[1;33m"; idle_c = ESC "[32m"; dead_c = ESC "[2;31m"
        run_g = run_c "⣽" rst; idle_g = idle_c "✓" rst; dead_g = dead_c "✝" rst
        ns = split(ENVIRON["pane_statuses"], S, "\n")
        for (i = 1; i <= ns; i++) {
            p = index(S[i], sep)
            if (p > 1) stat[substr(S[i], 1, p - 1)] = substr(S[i], p + 1)
        }
        if (mru_file != "") {
            while ((getline pid < mru_file) > 0)
                if (!(pid in seen)) { seen[pid] = 1; seq[++k] = pid }
            close(mru_file)
            for (i = k; i >= 1; i--) rank[seq[i]] = k - i + 1
        }
    }
    NF >= 8 {
        id = $1; tgt = $2; ses = $3; widx = $4 + 0; wnm = $5; cmd = $6; det = $8
        if (excl_current && tgt == cur) next
        r = (id in rank) ? rank[id] : 1000000 + ++fresh
        st = (id in stat) ? stat[id] : ""
        if (!(ses in srank) || r < srank[ses]) { srank[ses] = r; star[ses] = tgt }
        wk = ses SUBSEP widx
        if (!(wk in wrank) || r < wrank[wk]) { wrank[wk] = r; wtar[wk] = tgt; wnum[wk] = widx }
        wn[wk] = wnm
        if (st == "running") cnt[ses, "r"]++
        else if (st == "idle") cnt[ses, "i"]++
        else if (st == "dead") cnt[ses, "d"]++
        g = st == "running" ? run_g : st == "idle" ? idle_g : st == "dead" ? dead_g : ""
        # strip the default FMT prefix "cmd · "; index/substr are byte-based
        # in bwk awk, and " · " is 4 bytes in UTF-8 — same byte math everywhere
        tail = det
        p = index(tail, " · ")
        if (p > 1 && substr(tail, 1, p - 1) == cmd) tail = substr(tail, p + 4)
        b[id] = cmd (g != "" ? " " g : "") " " dim "· " tail rst
        pn[id] = r; pt[id] = tgt; pw[id] = wk
        wpanes[wk] = wpanes[wk] (wpanes[wk] != "" ? "\n" : "") id
        if (!(wk in wseen)) { wseen[wk] = 1; wslist[++m] = wk; wses[wk] = ses }
    }
    function wkey(wk) { return sprintf("%012d|%06d", wrank[wk], wnum[wk]) }
    function pkey(id) { return sprintf("%012d|%s", pn[id], pt[id]) }
    END {
        ns = 0
        for (s in srank) slist[++ns] = s
        for (i = 1; i <= ns; i++) for (j = i + 1; j <= ns; j++)
            if (sprintf("%012d%s", srank[slist[j]], slist[j]) < sprintf("%012d%s", srank[slist[i]], slist[i])) { t = slist[i]; slist[i] = slist[j]; slist[j] = t }
        for (si = 1; si <= ns; si++) {
            s = slist[si]
            counts = ""
            if (cnt[s, "r"]) counts = counts " " run_c "⣽" cnt[s, "r"] rst
            if (cnt[s, "i"]) counts = counts " " idle_c "✓" cnt[s, "i"] rst
            if (cnt[s, "d"]) counts = counts " " dead_c "✝" cnt[s, "d"] rst
            print star[s] sep bold "▸ " s rst counts
            nw = 0
            for (x = 1; x <= m; x++) if (wses[wslist[x]] == s) wkeys[++nw] = wslist[x]
            for (i = 1; i <= nw; i++) for (j = i + 1; j <= nw; j++)
                if (wkey(wkeys[j]) < wkey(wkeys[i])) { t = wkeys[i]; wkeys[i] = wkeys[j]; wkeys[j] = t }
            for (wi = 1; wi <= nw; wi++) {
                wk = wkeys[wi]
                np = split(wpanes[wk], plist, "\n")
                for (i = 1; i <= np; i++) for (j = i + 1; j <= np; j++)
                    if (pkey(plist[j]) < pkey(plist[i])) { t = plist[i]; plist[i] = plist[j]; plist[j] = t }
                wb = (wi == nw) ? "└" : "├"
                if (np == 1) {
                    print wtar[wk] sep "  " wb " " ital wnum[wk] " " wn[wk] rst dim " ─ " rst b[plist[1]]
                } else {
                    print wtar[wk] sep "  " wb " " ital wnum[wk] " " wn[wk] rst
                    for (pi = 1; pi <= np; pi++) {
                        pb = (pi == np) ? "└" : "├"
                        prefix = (wi == nw) ? "      " : "  │   "
                        print pt[plist[pi]] sep prefix pb " " b[plist[pi]]
                    }
                }
            }
        }
    }')
tree="$tree"$'\n[cancel]'"$sep"'[cancel]'

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
    if [[ "$action" == "kill" || "$action" == "join" ]]; then
        fzf_header=(--header 'Select target pane(s). Press TAB to mark multiple items.')
    else
        fzf_header=(--header 'Select target pane.')
    fi
    if [[ "$action" == "switch" || "$action" == "join" ]]; then
        # The tree leads; ANSI/delimiter/with-nth only affect how fzf shows and
        # searches field 2 — returned lines are still "target<sep>display".
        target_origin=$(printf '%s\n' "$tree" | fzf "${fzf_header[@]}" \
            --ansi --delimiter="$sep" --with-nth=2 \
            "${TMUX_FZF_PREVIEW_OPTIONS[@]}")
        target=${target_origin%%"$sep"*}
    else
        target_origin=$(printf "[current]\n%s\n[cancel]" "$panes" | fzf "${fzf_header[@]}" "${TMUX_FZF_PREVIEW_OPTIONS[@]}")
        target_origin=${target_origin/\[current\]/$current_pane_origin}
        target=$(echo "$target_origin" | sed 's/: .*//')
    fi
    [[ "$target_origin" == "[cancel]" || -z "$target_origin" ]] && exit
    if [[ "$action" == "switch" ]]; then
        zoom_active=$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#{window_zoomed_flag}')
        echo "$target" | sed -E 's/:.*//g' | xargs -I{} tmux switch-client $TMUX_FZF_CLIENT_ARG -t {}
        echo "$target" | sed -E 's/\..*//g' | xargs -I{} tmux select-window -t {}
        echo "$target" | xargs -I{} tmux select-pane -t {}
        # Record the pick even when the hooks from main.tmux are not installed
        # (scripts invoked directly, e.g. a custom key binding). Recording is
        # an idempotent append, so a double call from both paths is harmless.
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
