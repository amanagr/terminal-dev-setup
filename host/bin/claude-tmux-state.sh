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

# Diagnostic: set CLAUDE_HOOK_DEBUG=1 in ~/.claude/settings.json `env`
# to append every payload to /tmp/claude-hooks.log so the JSON schema
# (notably .notification_type, which isn't fully pinned by the public
# hook docs) can be verified from a live fire. Cheap when off.
if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
    printf '%s %s\n%s\n---\n' "$(date -Iseconds)" "$event" "$payload" \
        >> /tmp/claude-hooks.log 2>/dev/null || true
fi

case "$event" in
    user-prompt-submit|pre-tool-use) state=working ;;
    stop)               state=done ;;
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

# True when pane $1 is on-screen for a focused client right now: it must
# be its window's active pane AND some attached, OS-focused client must be
# sitting on that window. Lets the Stop handler tell "you watched it finish"
# (stay quiet) from "it finished while you were away" (raise the done bell).
# Relies on focus-events (set in tmux.conf) keeping #{client_flags} carrying
# `focused`.
pane_is_viewed() {
    local pane=$1 p_active p_win flags cwin
    read -r p_active p_win <<<"$(tmux display-message -p -t "$pane" \
        '#{pane_active} #{window_id}' 2>/dev/null)"
    [ "$p_active" = 1 ] || return 1
    while IFS='|' read -r flags cwin; do
        case "$flags" in
            *focused*) [ "$cwin" = "$p_win" ] && return 0 ;;
        esac
    done < <(tmux list-clients -F '#{client_flags}|#{window_id}' 2>/dev/null)
    return 1
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
            # Stop while you were already watching this pane = you saw it
            # finish, so stay quiet (idle) rather than raising the bell.
            if [ "$state" = done ] && pane_is_viewed "$pane"; then
                state=idle
            fi
            if [ "$state" = ended ]; then
                tmux set-option -p -u -t "$pane" @claude_state 2>/dev/null || true
            else
                tmux set-option -p -t "$pane" @claude_state "$state" 2>/dev/null || true
            fi
            adjust_interval
            # Bare `refresh-client -S` only refreshes whichever client
            # tmux happens to attribute to this connection (often the
            # most-recently-attached one); other attached clients
            # wouldn't see the new state until their own status-interval
            # ticked. Loop over every attached client and refresh each
            # by tty so multi-client setups stay in sync.
            tmux list-clients -F '#{client_tty}' 2>/dev/null \
                | while IFS= read -r tty; do
                      [ -n "$tty" ] && tmux refresh-client -S -t "$tty" 2>/dev/null || true
                  done
            exit 0
            ;;
    esac
    prev_pid=$pid
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
done

exit 0
