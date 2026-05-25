#!/usr/bin/env bash
# Clears the Claude "done / your turn" bell once you visit the pane.
#
# Wired to tmux's after-select-pane and pane-focus-in hooks (see
# tmux.conf), which pass the just-focused pane id as $1:
#   after-select-pane → you switched to the pane inside tmux
#   pane-focus-in     → you refocused the terminal window onto it
# Only a pane in @claude_state=done is touched — a `working` or
# `permission` pane is never cleared by a mere glance, since those
# need you to act, not just look. The fast-path (one show-options,
# then exit) keeps this cheap despite firing on every pane switch.
set -u
pane=${1:-}
[ -n "$pane" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

state=$(tmux show-options -pqv -t "$pane" @claude_state 2>/dev/null || true)
[ "$state" = done ] || exit 0

# Visited → drop the badge. Unset (not "idle") to match the value the
# state script leaves on session-end; both render as no glyph.
tmux set-option -p -u -t "$pane" @claude_state 2>/dev/null || true

# Refresh every attached client now so the tab clears immediately
# rather than on the next status-interval tick (mirrors the loop in
# claude-tmux-state.sh).
tmux list-clients -F '#{client_tty}' 2>/dev/null \
    | while IFS= read -r tty; do
          [ -n "$tty" ] && tmux refresh-client -S -t "$tty" 2>/dev/null || true
      done
exit 0
