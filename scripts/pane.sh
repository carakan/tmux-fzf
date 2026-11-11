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
    # "cmd · " prefix from the detail; the dim tail is the working directory
    # (shrunk fish-style by default, see TMUX_FZF_PANE_PATH_STYLE in the
    # README) plus the state flags. TMUX_FZF_PANE_FORMAT replaces this detail
    # wholesale (tree, status glyph and preview still wrap it).
    FMT='#{pane_current_command} · #{pane_current_path}#{?pane_active, ●,}#{?window_zoomed_flag, ⤢,}'
else
    FMT="$TMUX_FZF_PANE_FORMAT"
fi

# One list-panes pass carries everything the tree needs: pane_id (stable MRU
# key — S:W.P indices shift when windows close), the S:W.P target, session,
# window index, window name, current command, dead flag, the display detail,
# the raw working directory and the pane's process id for subprocess listing.
panes_raw=$(tmux list-panes -a -F "#{pane_id}${sep}#S:#{window_index}.#{pane_index}${sep}#S${sep}#{window_index}${sep}#{window_name}${sep}#{pane_current_command}${sep}#{pane_dead}${sep}${FMT}${sep}#{pane_current_path}${sep}#{pane_pid}")

# awk shape for both lists below: shorten every directory component but the
# last to its first character ("fish" — /u/s/wt), keep the full path ("full"),
# or reduce to the last component ("basename"). $HOME renders as ~.
dir_shrink='
    function shrink(path,    h, n, a, i, out, c) {
        h = ENVIRON["HOME"]
        if (h != "" && index(path, h) == 1) path = "~" substr(path, length(h) + 1)
        if (style == "full") return path
        n = split(path, a, "/")
        if (n <= 1) return path
        if (style == "basename") return a[n]
        out = ""
        for (i = 1; i < n; i++) {
            c = a[i]
            if (c == "") out = out "/"
            else if (c == "~") out = out "~/"
            else out = out substr(c, 1, substr(c, 1, 1) == "." ? 2 : 1) "/"
        }
        return out a[n]
    }
    function restyle(tail, path,    p) {
        if (path != "") {
            p = index(tail, path)
            if (p > 0) tail = substr(tail, 1, p - 1) shrink(path) substr(tail, p + length(path))
        }
        return tail
    }
    BEGIN {
        style = ENVIRON["TMUX_FZF_PANE_PATH_STYLE"]
        if (style != "fish" && style != "full" && style != "basename") style = "fish"
    }'

# Flat targets for the structural actions — the same "S:W.P: detail" shape
# .preview and the sed-based handlers already parse (only the display path is
# shrunk; handlers read what is left of ": ").
panes=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" "$dir_shrink"'
    BEGIN { FS = sep } NF >= 8 { print $2 ": " restyle($8, $9) }')

# Agent status — exact first, inferred otherwise, no daemon of our own. When
# the tmux-agent-status plugin tracks a pane, its hook-written cache files
# carry the real lifecycle state and we read that. For every other pane the
# status is inferred at picker-open time from the pane itself: a pane whose
# current command is a known coding agent gets its last output lines
# inspected; a spinner or "esc to interrupt" means running, anything else
# means the agent sits idle (turn done, waiting for you). Dead panes — any
# pane, agent or not — come straight from tmux's dead flag. Agent panes are
# found by walking the process tree: a pane is an agent pane when any
# process under its root pid has an agent command as its executable basename
# — or as the first argument's basename under an interpreter, so "node
# /path/to/bin/claude" registers as claude while "man claude" never does
# (approach ported from samleeney/tmux-agent-status agent-processes.sh).
agent_re='claude|codex|gemini|aider|copilot|cursor-agent|opencode|crush|amp|qwen|droid|omp|pi'
ps_tmp="$(mktemp "${TMPDIR:-/tmp}/tmux-fzf-ps.XXXXXX")"
ps -axo pid=,ppid=,stat=,command= > "$ps_tmp" 2>/dev/null || { rm -f "$ps_tmp"; ps_tmp=""; }
agent_roots=""
agent_rows=""
if [[ -n "$ps_tmp" ]]; then
    agent_rows=$(printf '%s' "$panes_raw" | awk -v sep="$sep" -v agent_re="$agent_re" -v ps_file="$ps_tmp" '
        function basename(s) { sub(".*/", "", s); return s }
        BEGIN {
            FS = sep
            while ((getline line < ps_file) > 0) {
                sub(/^[ \t]+/, "", line)
                gsub(/[ \t]+/, " ", line)
                if (index(line, " ") == 0) continue
                pid = substr(line, 1, index(line, " ") - 1); line = substr(line, index(line, " ") + 1)
                if (index(line, " ") == 0) continue
                ppid = substr(line, 1, index(line, " ") - 1); rest = substr(line, index(line, " ") + 1)
                if (index(rest, " ") == 0) continue
                args = substr(rest, index(rest, " ") + 1)
                ch[ppid] = ch[ppid] " " pid
                ag[pid] = args
            }
            close(ps_file)
        }
        # iterative walk of the subtree below root — no recursion; returns
        # the agent command name when found, "" when not
        function subtree_agent(root,    q, qi, n, cur, arr, i, nn, a, f, k) {
            q[1] = root; qi = 1; n = 1
            while (qi <= n) {
                cur = q[qi]; qi++
                a = ag[cur]
                if (a != "") {
                    nn = split(a, f, " ")
                    k = basename(f[1])
                    if (k ~ "^(" agent_re ")$") return k
                    if (k ~ /^(node|bun|deno|python[0-9.]*)$/ && nn >= 2 && basename(f[2]) ~ "^(" agent_re ")$") return basename(f[2])
                }
                nn = split(ch[cur], arr, " ")
                for (i = 1; i <= nn; i++) if (arr[i] != "") { n++; q[n] = arr[i] }
            }
            return ""
        }
        NF >= 10 { name = subtree_agent($10); if (name != "") print $10 sep name }
    ')
    agent_roots="$(printf '%s\n' "$agent_rows" | cut -d"$sep" -f1 | tr '\n' ' ')"
    export agent_names="$agent_rows"
fi
# tmux-agent-status cache: panes/<session>_<pane>.status holds one word
# (working|wait|ask|done); parked/<session>_<pane>.parked and
# wait/<session>_<pane>.wait (content: expiry epoch) override it. Resolution
# mirrors their get_pane_status, minus the session-level fallback — for that
# we keep our own inference.
tas_dir="$HOME/.cache/tmux-agent-status"
[ -d "$tas_dir" ] || tas_dir=""
tas_now=$(date +%s)
statuses=""
while IFS="$sep" read -r pid _ptarget _psess _pwin _pwinname pcmd pdead _pdetail _ppath _proot; do
    state=""
    if [[ "$pdead" == "1" ]]; then
        state=dead
    elif [[ " $agent_roots " == *" ${_proot} "* || -n "$tas_dir" && -f "$tas_dir/panes/${_psess}_${pid}.agent" ]]; then
        if [[ -n "$tas_dir" ]]; then
            if [[ -f "$tas_dir/parked/${_psess}_${pid}.parked" ]]; then
                state=parked
            else
                if [[ -f "$tas_dir/wait/${_psess}_${pid}.wait" ]]; then
                    expiry=$(cat "$tas_dir/wait/${_psess}_${pid}.wait" 2>/dev/null)
                    if [[ "$expiry" =~ ^[0-9]+$ ]] && (( expiry > tas_now )); then
                        state=wait
                    else
                        # expired: clean up exactly like their reader does
                        rm -f "$tas_dir/wait/${_psess}_${pid}.wait"
                        [[ "$(cat "$tas_dir/panes/${_psess}_${pid}.status" 2>/dev/null)" == "wait" ]] &&
                            printf 'done\n' > "$tas_dir/panes/${_psess}_${pid}.status"
                    fi
                fi
                if [[ -z "$state" ]]; then
                    case "$(cat "$tas_dir/panes/${_psess}_${pid}.status" 2>/dev/null)" in
                        working) state=running ;;
                        ask) state=ask ;;
                        wait) state=wait ;;
                        done) state=idle ;;
                    esac
                fi
            fi
        fi
        if [[ -z "$state" ]]; then
            if tmux capture-pane -p -t "$pid" -S -5 2>/dev/null |
                grep -qE '⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|⣾|⣽|⣻|⣿|⣯|⣷|⣟|esc to interrupt|✢|✳|✶|✻|✽|✦|Thinking'; then
                state=running
            else
                state=idle
            fi
        fi
    fi
    [ -n "$state" ] && statuses+="${pid}${sep}${state}"$'\n'
done <<< "$panes_raw"
export pane_statuses="$statuses"

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
tree=$(printf '%s\n' "$panes_raw" | awk -v sep="$sep" \
    -v mru_file="$mru_file" \
    -v excl_current=$([[ -z "$TMUX_FZF_SWITCH_CURRENT" ]] && echo 1 || echo 0) \
    -v cur="$current_pane" \
    -v ps_file="$ps_tmp" "$dir_shrink"'

    BEGIN {
        FS = sep
        ESC = sprintf("%c", 27)
        bold = ESC "[1m"; ital = ESC "[3m"; dim = ESC "[2m"; rst = ESC "[0m"
        run_c = ESC "[1;33m"; idle_c = ESC "[32m"; dead_c = ESC "[2;31m"
        ask_c = ESC "[1;31m"; wait_c = ESC "[36m"; parked_c = ESC "[2m"
        run_g = run_c "⣽" rst; idle_g = idle_c "✓" rst; dead_g = dead_c "✝" rst
        ask_g = ask_c "❓" rst; wait_g = wait_c "⏳" rst; parked_g = parked_c "⏸" rst
        # ps snapshot: pid, ppid, stat, command — children grouped by root pid
        # (ps sorts by pid, so each group keeps ascending order; at most one
        # line per pid: a later duplicate child wins)
        if (ps_file != "") {
            while ((getline line < ps_file) > 0) {
                sub(/^[ \t]+/, "", line)
                gsub(/[ \t]+/, " ", line)   # ps aligns columns; collapse runs
                if (index(line, " ") == 0) continue
                pid1 = substr(line, 1, index(line, " ") - 1); line = substr(line, index(line, " ") + 1)
                if (index(line, " ") == 0) continue
                ppid1 = substr(line, 1, index(line, " ") - 1); line = substr(line, index(line, " ") + 1)
                if (index(line, " ") == 0) continue
                stat1 = substr(line, 1, index(line, " ") - 1); cmd1 = substr(line, index(line, " ") + 1)
                if (ppid1 + 0 > 1 && pid1 + 0 > 1) kids_of[ppid1] = kids_of[ppid1] pid1 sep stat1 sep cmd1 "\n"
            }
            close(ps_file)
        }
        # wrapper-detected agents: pane root pid → the agent command name the
        # pane is displayed under (claude for node /path/to/bin/claude)
        ns2 = split(ENVIRON["agent_names"], AN, "\n")
        for (i = 1; i <= ns2; i++) {
            p = index(AN[i], sep)
            if (p > 1) aname[substr(AN[i], 1, p - 1)] = substr(AN[i], p + 1)
        }
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
        if ($10 in aname) cmd = aname[$10]
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
        else if (st == "ask") cnt[ses, "a"]++
        g = st == "running" ? run_g : st == "idle" ? idle_g : st == "ask" ? ask_g : st == "wait" ? wait_g : st == "parked" ? parked_g : st == "dead" ? dead_g : ""
        # strip the default FMT prefix "cmd · "; index/substr are byte-based
        # in bwk awk, and " · " is 4 bytes in UTF-8 — same byte math everywhere
        tail = det
        p = index(tail, " · ")
        if (p > 1 && substr(tail, 1, p - 1) == cmd) tail = substr(tail, p + 4)
        tail = restyle(tail, $9)
        b[id] = cmd (g != "" ? " " g : "") " " dim "· " tail rst
        pn[id] = r; pt[id] = tgt; pw[id] = wk
        kid[id] = (st != "" && st != "dead") ? $10 : ""
        wpanes[wk] = wpanes[wk] (wpanes[wk] != "" ? "\n" : "") id
        if (!(wk in wseen)) { wseen[wk] = 1; wslist[++m] = wk; wses[wk] = ses }
    }
    function wkey(wk) { return sprintf("%012d|%06d", wrank[wk], wnum[wk]) }
    function pkey(id) { return sprintf("%012d|%s", pn[id], pt[id]) }
    # descendants of an agent pane, walked breadth-first from the ps snapshot;
    # each line keeps the pane jump target so picking a subprocess lands in
    # that pane. Cap: first three plus a count line.
    function print_kids(tgt, root, indent,    q, dp, qi, n, cur, arr, i, nn, p, kpid, kstat, kcmd, kcs, kg, total, show, pad) {
        if (root == "" || !(root in kids_of)) return
        q[1] = root; dp[1] = 1; qi = 1; n = 1; total = 0
        while (qi <= n) {
            cur = q[qi]; cdp = dp[qi]; qi++
            nn = split(kids_of[cur], arr, "\n")
            for (i = 1; i <= nn; i++) {
                if (arr[i] == "") continue
                p = index(arr[i], sep); kpid = substr(arr[i], 1, p - 1); arr[i] = substr(arr[i], p + 1)
                p = index(arr[i], sep); kstat = substr(arr[i], 1, p - 1); kcmd = substr(arr[i], p + 1)
                total++
                if (total <= 3) {
                    kcs = substr(kstat, 1, 1)
                    kg = kcs == "Z" ? dead_c "✝" : kcs == "R" ? run_c "▸" : kcs == "T" ? parked_c "⏸" : dim "·"
                    show = substr(kcmd, 1, 56)
                    pad = (cdp == 1) ? "    " : "      "
                    print tgt sep indent pad dim "└" rst " " kg rst " " dim show (length(kcmd) > 56 ? "…" : "") rst
                }
                n++; q[n] = kpid; dp[n] = cdp + 1
            }
        }
        if (total > 3) print tgt sep indent "    " dim "└ +" total - 3 " subprocesses" rst
    }
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
            if (cnt[s, "a"]) counts = counts " " ask_c "❓" cnt[s, "a"] rst
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
                    print_kids(pt[plist[1]], kid[plist[1]], "  ")
                } else {
                    print wtar[wk] sep "  " wb " " ital wnum[wk] " " wn[wk] rst
                    for (pi = 1; pi <= np; pi++) {
                        pb = (pi == np) ? "└" : "├"
                        prefix = (wi == nw) ? "      " : "  │   "
                        print pt[plist[pi]] sep prefix pb " " b[plist[pi]]
                        print_kids(pt[plist[pi]], kid[plist[pi]], prefix)
                    }
                }
            }
        }
    }')
rm -f "$ps_tmp"
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
