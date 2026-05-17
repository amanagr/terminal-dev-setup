#!/usr/bin/env bash
# Sets the per-pane @claude_state tmux option from a Claude Code
# hook event, so window-status-format (via claude-tmux-status.sh) can
# render a pulsing dot / warning / process icon on the tab.
#
# Usage: claude-tmux-state.sh <event>
#   event: user-prompt-submit | pre-tool-use | stop |
#          notification | session-start | session-end
#
# `pre-tool-use` flips the tab back to `working` the moment a tool
# starts (i.e. right after the user grants a permission prompt) so
# the ⚠ doesn't linger until Stop. It's also harmlessly idempotent
# for tools that don't need permission — state is already `working`.
#
# Hook JSON is read from stdin and (for `notification`) inspected for
# `notification_type` to map permission_prompt/elicitation_dialog →
# permission, idle_prompt → idle.
#
# State is scoped to the pane (not the window) so two claude panes in
# the same tmux window don't stomp each other's state — a finishing
# claude won't flip the tab to `idle` while a sibling pane is still
# `working`. claude-tmux-status.sh aggregates the per-pane states up
# to the tab with priority permission > working > none.
#
# After each state change, status-interval is auto-tuned globally:
#   1s when any pane is `working` (so the dot animates)
#   5s otherwise (the static icons don't need fast refresh)
#
# Resolves the calling pane by walking parent PIDs up to the tmux
# server; the pid immediately below it is the pane's shell, which
# `tmux list-panes -a` maps back to a pane id.

set -u

event=${1:-}
payload=$(cat 2>/dev/null || true)

case "$event" in
    user-prompt-submit|pre-tool-use) state=working ;;
    stop)               state=idle ;;
    session-end)        state=ended ;;
    session-start)      state=idle ;;
    notification)
        ntype=$(jq -r '.notification_type // empty' <<<"$payload" 2>/dev/null || true)
        case "$ntype" in
            permission_prompt|elicitation_dialog) state=permission ;;
            idle_prompt) state=idle ;;
            *) exit 0 ;;
        esac
        ;;
    *) exit 0 ;;
esac

command -v tmux >/dev/null 2>&1 || exit 0

adjust_interval() {
    local any_working
    any_working=$(tmux list-panes -a -F '#{@claude_state}' 2>/dev/null \
        | grep -cx working || true)
    if [ "${any_working:-0}" -gt 0 ]; then
        tmux set-option -g status-interval 1 2>/dev/null || true
    else
        tmux set-option -g status-interval 5 2>/dev/null || true
    fi
}

pid=$PPID
prev_pid=
while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    # ${comm##*/} strips any leading absolute path — macOS `ps -o comm=`
    # returns the full path (e.g. /opt/homebrew/bin/tmux) when tmux was
    # launched with one, which broke the bare `tmux*` glob.
    case "${comm##*/}" in
        tmux*)
            [ -n "$prev_pid" ] || exit 0
            pane=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null \
                | awk -v p="$prev_pid" '$1==p {print $2; exit}')
            [ -n "$pane" ] || exit 0
            if [ "$state" = ended ]; then
                tmux set-option -p -u -t "$pane" @claude_state 2>/dev/null || true
            else
                tmux set-option -p -t "$pane" @claude_state "$state" 2>/dev/null || true
            fi
            adjust_interval
            tmux refresh-client -S 2>/dev/null || true
            exit 0
            ;;
    esac
    prev_pid=$pid
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
done

exit 0
