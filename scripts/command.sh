#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/.envs"

target_origin=$(tmux list-commands)
target=$(printf "[cancel]\n%s" "$target_origin" | fzf --header 'Select a command.' | cut -d ' ' -f 1)

[[ "$target" == "[cancel]" || -z "$target" ]] && exit
tmux command-prompt -I "$target"
