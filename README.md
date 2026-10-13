![demo](https://gitlab.com/sainnhe/img/-/raw/master/tmux-fzf.gif)

# Features

- Manage sessions (switch, new, rename, detach, kill).
- Manage windows (switch, link, move, swap, rename, kill).
- Manage panes (switch, break, join, swap, layout, kill, resize).
- Search commands and append to command prompt.
- Search key bindings and execute.
- Search clipboard history and paste to current window.
- Process management (top, pstree, terminate, kill, interrupt, continue, stop, quit, hangup).
- User menu (run custom commands).
- Preview sessions, windows and panes.
- Multiple selection.

# Installation

## Requirements

- [GNU bash](https://www.gnu.org/software/bash/)
- [sed](https://www.gnu.org/software/sed/)
- [junegunn/fzf](https://github.com/junegunn/fzf/) ≥ 0.53 (native `--tmux` popups)
- tmux ≥ 3.3 (popup requirement of current fzf; tmux < 3.2 has no popups at all)
- [CopyQ](https://github.com/hluk/CopyQ/) (optional): Access system clipboard, fallback to builtin tmux buffers if copyq is not executable.
- [pstree](https://gitlab.com/psmisc/psmisc/) (optional): Display process tree.

**Note:** Please use this command to check whether tmux is able to find fzf [#1](https://github.com/sainnhe/tmux-fzf/issues/1): `tmux run-shell -b 'command -v fzf'`

## Install via [TPM](https://github.com/tmux-plugins/tpm/)

Add this line to your `~/.tmux.conf`

```tmux
set -g @plugin 'sainnhe/tmux-fzf'
```

Reload configuration, then press `prefix` + `I` (Shift+I).

# Usage

To launch tmux-fzf, press `prefix` + `F` (Shift+F).

This plugin supports multiple selection for some actions, you can press `TAB` and `Shift-TAB` to mark multiple items.

Most of the features work out of the box, but there are some features that need to be explained here.

## Kill Window(s)

The `kill` action in tmux-fzf actually uses `tmux unlink-window -k` instead of `tmux kill-window`.

The main difference between `unlink-window -k` and `kill-window` is that `kill-window` will kill current window and all other windows linked to it, while `unlink-window -k` will only kill current window.

The logic of `unlink -k` is a bit like hard links. If the current window only exists in one session, then kill; if the current window exists in multiple sessions, then unlink.

Btw, if you want to bind a key to kill current window, I would recommend `unlink-window -k` instead of `kill`.

## User Menu

You can add a custom menu to quickly execute some commands.

This feature is not enabled by default. To enable it, add something like this to `~/.tmux.conf`

```tmux
TMUX_FZF_MENU=\
"foo\necho 'Hello!'\n"\
"bar\nls ~\n"\
"sh\nsh ~/test.sh\n"
```

When you launch tmux-fzf, an extra item named `menu` will appear. Selecting this item will produce [this](https://user-images.githubusercontent.com/37491630/66251156-71836000-e73c-11e9-809d-e865651f8d7d.png).

There will be 3 items to select from: `foo`, `bar` and `sh`.

When you select `foo`, tmux will execute `echo 'Hello!'`.

When you select `bar`, tmux will execute `ls ~`.

When you select `sh`, tmux will execute `sh ~/test.sh`.

**Note:**

- `foo` and `echo 'hello'` are separated by `\n` in `TMUX_FZF_MENU`, and you need to add another `\n` after `echo 'hello'`.
- **DO NOT** add additional white spaces/tabs at the beginning of each line.
- Commands are executed using `tmux -c`, so please make sure `tmux -c "your command"` does work.

### Alternative format for TMUX_FZF_MENU

Here each menu item (`name + command`) consist of 3 lines:

1. name: Name of the item on the menu selection.
2. command: what will be execute when you select that item on the menu.
3. end of line (menu item): required end of line per menu item.

```tmux
TMUX_FZF_MENU="\
foo\n\              <- name
echo 'Hello!'\      <- command
\n""\               <- end of line
bar\n\
ls ~\
\n""\
sh\n\
sh ~/test.sh\
\n""\
nil--\n\n"          <- this is required
```

### Menu Popup

You can configure the menu output to appear on a popup window instead of the current pane you're on.

To enable this set the `TMUX_FZF_MENU_POPUP=1` variable.

You can also set the width and height for the popup window.

Default values:

```
TMUX_FZF_MENU_POPUP_WIDTH=50%
TMUX_FZF_MENU_POPUP_HEIGHT=50%
```

## Popup Window

Every picker opens as a tmux popup (`fzf --tmux`), which requires tmux ≥ 3.2; current fzf raises that to tmux ≥ 3.3. fzf ignores the popup flag entirely outside tmux, so the scripts also work from a bare shell.

The default geometry is `center,62%,38%`, on compact clients `center,96%,88%` — see [Mobile and narrow clients](#mobile-and-narrow-clients). To change it, add your own `--tmux` flag to `FZF_DEFAULT_OPTS`, see [Fzf Behavior](#fzf-behavior).

# Customization

## Key Binding

The plugin binds `prefix` + `F` when it loads. For another key, set the launch key **before** the plugin manager line in `~/.tmux.conf` — `main.tmux` reads it from the tmux global environment and binds it on every reload, so there is no ordering race:

```tmux
set-environment -g TMUX_FZF_LAUNCH_KEY "C-f"
run '~/.tmux/plugins/tpm/tpm'
```

To bind the key by hand instead, do it **after** the plugin manager line, and pass both variables along — the scripts run detached and would otherwise fall back to the most recently active client and lose the screen geometry (see below):

```tmux
run '~/.tmux/plugins/tpm/tpm'
bind-key C-f run-shell -b "TMUX_FZF_CLIENT='#{client_tty}' TMUX_FZF_CLIENT_WIDTH='#{client_width}' '#{TMUX_FZF_DIR}/main.sh'"
```

If you keep plugins outside `~/.tmux/plugins` (a custom `TPM_PLUGIN_DIR`), point the plugin at them — the launch key would otherwise target a directory without a `main.sh`:

```tmux
set-environment -g TMUX_FZF_DIR /opt/tpm/tmux-fzf
```

## Mobile and narrow clients

`main.tmux` hands the picker the geometry of the client that pressed the key — `TMUX_FZF_CLIENT_WIDTH` and `TMUX_FZF_CLIENT_HEIGHT`. The picker switches to a compact layout when **either** dimension is below a fixed threshold — 140 columns or 30 rows:

```
-p -w 96% -h 88% -m --info=inline --padding='1,0,0,0'
```

with the preview pane turned off. Both dimensions matter: a phone in portrait is wide and short (Termius reports roughly `430x65`), while a landscape phone or a short split terminal is *narrow in rows and wide in columns* — the 60 % popup then leaves a dozen usable lines. A width-only check never caught that case.

The geometry is a native fzf flag now: `--tmux center,96%,88%` asks fzf to open the popup 96 % wide and 88 % tall, and tmux resolves and clamps the percentages itself — the popup chrome, positioning and clamping are tmux's job.

Your own options always win: `fzf` applies `FZF_DEFAULT_OPTS` with last-occurrence-wins, so a `--tmux` flag you add there replaces the plugin's geometry — on the phone too. That is the supported way to pin a layout.

## MRU pane ordering

`prefix` + pane switch lists panes **most-recently-used first**, then never-used panes in tmux order, so the list reads like Alt-Tab.

Recording happens in `after-select-pane` and `after-select-window` hooks installed by `main.tmux`, which means every switch counts — picker picks, vim keys, clicks, window jumps — not only picks made in the picker. A record is a single append to `${XDG_CACHE_HOME:-~/.cache}/tmux-fzf-pane-mru` (atomic, no locking), keyed by `pane_id` (`%N`): `session:window.pane` indices shift when windows close, so an index-keyed entry would eventually point at a different pane. Entries for dead panes are pruned when the picker opens.

| variable | default | meaning |
| --- | --- | --- |
| `TMUX_FZF_MRU` | `1` | `0` restores plain index order and stops recording |

Inspect or reset the order with the helper:

```sh
scripts/mru.sh list    # newest first
scripts/mru.sh prune   # drop entries for panes that no longer exist
scripts/mru.sh file    # print the log path
```

## Fzf Behavior

The plugin configures `fzf` through the very variable `fzf` already reads: every picker **prepends** its defaults to `FZF_DEFAULT_OPTS` —

```
--tmux center,62%,38% -m
```

(`--tmux center,96%,88% -m --info=inline --padding 1,0,0,0` on compact clients) — and then your own `FZF_DEFAULT_OPTS` follows, where later occurrences win. To change the popup geometry, add your own `--tmux` flag; to change anything else, add the flag. To list all available options, execute `fzf --help` in your shell.

### Sharing one set of options with your shell

The cleanest setup is to configure `fzf` once, with the plain variables it
already reads, and let the pickers inherit them: set `FZF_COLORS` for the
palette and `FZF_DEFAULT_OPTS` for options, then push both into tmux. The popup
pane is created by the tmux server and inherits the **global** environment store
(verified on tmux 3.8 — including for a session created before the variable
existed), so no `TMUX_FZF_*` copy is needed:

```sh
# ~/.zshrc
export FZF_COLORS='fg:#FEF9E1,bg:#282828,pointer:#d4be98'
export FZF_DEFAULT_OPTS='--no-bold'
if [ -n "$TMUX" ]; then
    for v in FZF_COLORS FZF_DEFAULT_OPTS; do
        tmux set-environment -g "$v" "${(P)v}"
        tmux set-environment -t "$(tmux display-message -p '#S')" "$v" "${(P)v}"
    done
fi
```

Colors then need no `--color` anywhere: `fzf` reads `FZF_COLORS` itself, and the plugin's per-picker command-line options (headers, its own preview window) take precedence over the inherited options.

`FZF_DEFAULT_OPTS` is data to the pickers, not code: nothing is `eval`'d anymore — `fzf` parses it with its own shell-word rules. Flags with spaces or `=`-forms are fine; `$(…)`, backticks and `;` are passed to `fzf` literally.

`update-environment` is *not* an alternative here: it copies from the client's
environment — the terminal process, which never had these values, since they are
exported later by the interactive shell.

### Migrating from `TMUX_FZF_OPTIONS`

The old variable is gone. Move its flags into the `FZF_DEFAULT_OPTS` you push into tmux (same recipe as above), with two rewrites:

- popup flags: `-p -w 60% -h 60%` → `--tmux center,60%,60%` (`--tmux` is a real `fzf` flag now);
- `--color=$FZF_COLORS` expansions: delete them, `fzf` reads `FZF_COLORS` natively — that eval trick was the reason `TMUX_FZF_OPTIONS` had to be shell-eval'd, and it no longer exists.

```tmux
# before: set-environment -g TMUX_FZF_OPTIONS "-p -w 60% -h 60% -m --border=rounded"
# after (e.g. from ~/.zshrc, then push):
export FZF_DEFAULT_OPTS="--tmux center,60%,60% -m --border=rounded ${FZF_DEFAULT_OPTS}"
```

Options the plugin puts on the command line win over the inherited ones, so the
popup keeps its `-p` positioning and geometry while still using your colors and
your key bindings. Two caveats come with sharing the variable: a `--preview` in
`FZF_DEFAULT_OPTS` reaches every picker that passes no preview options of its
own, and `--bind` entries *merge* with the plugin's rather than replacing them,
so the plugin cannot turn a binding off once it is inherited.

## Preview

Preview is enabled by default. To hide it, add something like this to your `~/.tmux.conf`:

```tmux
TMUX_FZF_PREVIEW=0
```

Then the preview window will be hidden until `toggle-preview` is triggered.

The preview window always tries to "follow" the content (see description in [the fzf docs](https://github.com/junegunn/fzf/blob/master/ADVANCED.md#log-tailing)).

## Order

To customize the order of the actions, add something like this to your `~/.tmux.conf`:

```tmux
TMUX_FZF_ORDER="session|window|pane|command|keybinding|clipboard|process"
```

You can also use this variable to disable unwanted features. For example, to disable `clipboard` and `process`, simply delete them in `$TMUX_FZF_ORDER`:

```tmux
TMUX_FZF_ORDER="session|window|pane|command|keybinding"
```

## Format

For some reasons, you may want to customize format of panes, windows, sessions listed in fzf. There are three variables to complete this work:

`TMUX_FZF_PANE_FORMAT`   `TMUX_FZF_WINDOW_FORMAT`   `TMUX_FZF_SESSION_FORMAT`

For example, `tmux list-panes -a` doesn't show running program and window name by default. If you want to show running program and window name, add something like this to `~/.tmux.conf`

```tmux
TMUX_FZF_PANE_FORMAT="[#{window_name}] #{pane_current_command}  [#{pane_width}x#{pane_height}] [history #{history_size}/#{history_limit}, #{history_bytes} bytes] #{?pane_active,[active],[inactive]}"
```

Similarly, `TMUX_FZF_WINDOW_FORMAT` and `TMUX_FZF_SESSION_FORMAT` can also be handled in this way.

For more information, check "FORMATS" section in tmux manual.


## Filter

By default, the current session, window, and pane, are not listed among the switch possibilities. To include it, set:

```tmux
TMUX_FZF_SWITCH_CURRENT=1
```

When using the window listing script, it is possible to filter its output. This relies on the tmux filtering feature with a specific syntax for filters. For more information about this feature, check "FORMATS" section in the tmux manual.

To use this filtering feature, set the variable `TMUX_FZF_WINDOW_FILTER` to the filter you want to apply before calling the `window.sh` script. 

## Multiple Attached Clients

When several tmux clients are attached to the same server (e.g. two terminals), tmux commands that need a client context have to know *which* client opened the menu. Since the scripts are executed detached via `run-shell -b`, tmux would otherwise fall back to the most recently active client - which may be the other terminal. This can make `switch` act on the wrong screen and may cause intermittent `'... returned 1'` errors.

To pin all client-dependent commands to the client that opened the menu, the default launch key binding passes `#{client_tty}` via `$TMUX_FZF_CLIENT` automatically. If you call the scripts from your own key bindings, pass it yourself:

```tmux
bind-key a run-shell -b "TMUX_FZF_CLIENT='#{client_tty}' ~/.tmux/plugins/tmux-fzf/scripts/session.sh switch"
```

If `$TMUX_FZF_CLIENT` is unset, the behavior is unchanged (most recently active client).

# FAQ

**Q: Why use environment variables instead of tmux options to customize this plugin?**

**A:** Because the performance of tmux options is very bad. I pushed a branch named `tmux-options` to demonstrate how bad the performance will be if we use tmux options to customize this plugin, you can checkout this branch and get it a try.

**Q: How to launch tmux-fzf with preselected action?**

**A:** See [#6](https://github.com/sainnhe/tmux-fzf/issues/6).

**Q: What's your status line configuration?**

**A:** See this [post](https://www.sainnhe.dev/post/status-line-config/).

**Q: What's the color scheme used in the screenshot?**

**A:** [Gruvbox Material](https://github.com/sainnhe/gruvbox-material)

# More plugins

- [sainnhe/tmux-translator](https://github.com/sainnhe/tmux-translator): A translation plugin powered by popup window.

# Tests

`test/run.sh` runs the suite — no live tmux server and no real `fzf` needed, both are stubbed (`test/lib.sh` builds the stubs, every case runs in its own sandbox with a scrubbed environment):

```sh
test/run.sh          # everything
test/run.sh mru      # cases matching a substring
```

Covered: `mru.sh` (append atomicity under concurrency, prune dedupe/dead/cap, ordering), `.envs` (geometry + `FZF_DEFAULT_OPTS` construction, compact detection, preview arrays), `pane.sh switch` end-to-end (picker order, recorded pick, exact argv/env shape), and the no-eval invariant (user-facing options must stay data, never shell input).

# License

Other code is distributed under [MIT](./LICENSE) && [Anti-996](./Anti-996-LICENSE).
