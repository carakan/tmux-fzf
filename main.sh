#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$TMUX_FZF_ORDER" ]] && TMUX_FZF_ORDER="copy-mode|session|window|pane|command|keybinding|clipboard|process"
source "$CURRENT_DIR/scripts/.envs"

items_origin="$(echo $TMUX_FZF_ORDER | tr '|' '\n')"

# remove copy-mode from options if we aren't in copy-mode
if [ "$(tmux display-message -p $TMUX_FZF_CLIENT_ARG '#{pane_in_mode}')" -eq 0 ]; then
    items_origin="$(echo "${items_origin}" | sed '/copy-mode/d')"
fi

if [[ ! -z "$TMUX_FZF_MENU" ]]; then
    items_origin+=$'\nmenu'
fi
items_origin+=$'\n[cancel]'
# Same eval as every other script: $TMUX_FZF_OPTIONS can contain shell
# expansions (--color=$FZF_COLORS is the documented example), and without eval
# fzf receives the literal string and rejects it with
# "invalid color specification: $FZF_COLORS" — the menu then dies silently.
item=$(echo "${items_origin}" | eval "$TMUX_FZF_BIN $TMUX_FZF_OPTIONS")
[[ "$item" == "[cancel]" || -z "$item" ]] && exit
# Hand the client geometry on to the sub-picker: scripts/.envs keys the whole
# compact layout off these two, so a picker launched without them would fall
# back to the desktop popup on a phone — the menu above is only the first hop.
tmux run-shell -b "TMUX_FZF_CLIENT='$TMUX_FZF_CLIENT' TMUX_FZF_CLIENT_WIDTH='$TMUX_FZF_CLIENT_WIDTH' TMUX_FZF_CLIENT_HEIGHT='$TMUX_FZF_CLIENT_HEIGHT' $CURRENT_DIR/scripts/${item}.sh"
