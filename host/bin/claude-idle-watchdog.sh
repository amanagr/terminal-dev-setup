#!/usr/bin/env bash
# Auto-exit a Claude Code session if it stays idle past a timeout.
#
# Usage: claude-idle-watchdog.sh <event>
#   event: arm    — start (or restart) the idle timer for this pane
#          cancel — cancel any pending timer for this pane
#
# Wired into Claude Code hooks:
#   Stop, Notification        → arm
#   UserPromptSubmit, PreToolUse, SessionEnd → cancel
#
# Pane resolution mirrors claude-tmux-state.sh (walk PPIDs to the tmux
# server, then map the immediate child back to a pane id). The timer
# is a fully detached background process keyed by pane id; its pid is
# stashed under $XDG_RUNTIME_DIR/claude-idle/<pane>.pid so a subsequent
# `cancel` can kill it.
#
# Before exiting the session, the watchdog re-reads the pane's
# @claude_state — if the user came back and started a new turn, the
# state will be `working` and the watchdog leaves the pane alone. The
# exit itself is `/exit` sent via `tmux send-keys`, which mirrors the
# keystrokes a user would type and lets claude tear down cleanly.
#
# Timeout is CLAUDE_IDLE_TIMEOUT seconds (default 36000 = 10 hr). Set
# to 0 to disable.

set -u

event=${1:-}
timeout=${CLAUDE_IDLE_TIMEOUT:-36000}
[ "$timeout" -gt 0 ] 2>/dev/null || exit 0

command -v tmux >/dev/null 2>&1 || exit 0

state_dir="${XDG_RUNTIME_DIR:-/tmp}/claude-idle"
mkdir -p "$state_dir" 2>/dev/null || exit 0

pid=$PPID
prev_pid=
pane=
while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    case "$comm" in
        tmux*)
            [ -n "$prev_pid" ] || exit 0
            pane=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null \
                | awk -v p="$prev_pid" '$1==p {print $2; exit}')
            break
            ;;
    esac
    prev_pid=$pid
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
done
[ -n "$pane" ] || exit 0

state_file="$state_dir/${pane#%}.pid"

cancel_existing() {
    [ -f "$state_file" ] || return 0
    old=$(cat "$state_file" 2>/dev/null || true)
    if [ -n "$old" ]; then
        # kill the subshell's `sleep` child first (TERM doesn't
        # propagate through a backgrounded subshell), then the
        # subshell itself.
        pkill -P "$old" 2>/dev/null || true
        kill "$old" 2>/dev/null || true
    fi
    rm -f "$state_file"
}

case "$event" in
    cancel)
        cancel_existing
        ;;
    arm)
        cancel_existing
        # Backgrounded subshell with all fds redirected so the hook
        # returns immediately and claude doesn't wait on it. `disown`
        # detaches it from this shell's job table; the subshell pid is
        # stashed so `cancel` can kill it cleanly.
        (
            sleep "$timeout"
            cur=$(tmux show-options -p -t "$pane" -v @claude_state 2>/dev/null || true)
            case "$cur" in
                idle|permission)
                    tmux send-keys -t "$pane" '/exit' Enter 2>/dev/null || true
                    ;;
            esac
            rm -f "$state_file"
        ) </dev/null >/dev/null 2>&1 &
        wpid=$!
        disown 2>/dev/null || true
        echo "$wpid" > "$state_file"
        ;;
esac

exit 0
