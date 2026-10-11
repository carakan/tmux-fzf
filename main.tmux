#!/usr/bin/env bash
# tmux-fzf — launcher wiring, run by TPM.
#
# TPM executes a plugin's *.tmux file as a shell script with its output
# discarded (tpm/scripts/source_plugins.sh: `$tmux_file >/dev/null 2>&1`), so
# this file is bash calling tmux subcommands — tmux config syntax here would
# fail with "set-environment: not found" and every binding would silently not
# exist. Errors are invisible for the same reason: keep it small, quiet and
# dependency-free. See tmux-resurrect/resurrect.tmux for the same pattern.
#
# Configurable through the tmux global environment (all optional):
#   TMUX_FZF_DIR            plugin location (default ~/.tmux/plugins/tmux-fzf).
#                           TPM_PLUGIN_DIR users must set this, otherwise the
#                           launch key would point at a directory that has no
#                           main.sh.
#   TMUX_FZF_LAUNCH_KEY     key for the picker (default F). Set it *before* the
#                           TPM line in tmux.conf, or bind the key by hand
#                           after the TPM line as documented in the README.

# The global environment is authoritative: TPM runs this script as a child of
# the tmux server process, so $TMUX_FZF_DIR here is whatever the server had at
# startup, not what `set-environment -g` changed since.
global_env() {
    tmux show-environment -g "$1" 2>/dev/null | sed -n "s/^$1=//p"
}

plugin_dir="$(global_env TMUX_FZF_DIR)"
[ -n "$plugin_dir" ] || plugin_dir="${TMUX_FZF_DIR:-$HOME/.tmux/plugins/tmux-fzf}"
launch_key="$(global_env TMUX_FZF_LAUNCH_KEY)"
[ -n "$launch_key" ] || launch_key="${TMUX_FZF_LAUNCH_KEY:-F}"

# So '#{TMUX_FZF_DIR}' also resolves in bind-key and run-shell commands.
tmux set-environment -g TMUX_FZF_DIR "$plugin_dir"

# The picker runs detached from the client that pressed the key: pin it, and
# hand over that client's geometry so scripts/.envs can pick a layout for the
# screen it actually opens on (a phone over Termius reports ~430x65 in
# portrait, but a landscape phone or a short split terminal is wide *and*
# cramped — width alone does not catch that).
tmux bind-key "$launch_key" run-shell -b \
    "TMUX_FZF_CLIENT='#{client_tty}' TMUX_FZF_CLIENT_WIDTH='#{client_width}' TMUX_FZF_CLIENT_HEIGHT='#{client_height}' '$plugin_dir/main.sh'"
