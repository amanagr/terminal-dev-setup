#!/usr/bin/env bash
# Headless-container attention hook. The container has no desktop session, so it
# can't pop a toast itself. It does two things that DO cross the boundary:
#   1. Rings a terminal BEL (\a) to /dev/tty — rides the vagrant-ssh / VSCode pty
#      to the host pane, where tmux's monitor-bell highlights the window tab.
#   2. Drops an attention marker into the bind-mounted worktree
#      ($WORKTREE_DIR/.claude-vm-attention = "<reason> <epoch>"). On the bell, the
#      host tmux's alert-bell hook (claude-vm-notify.sh) reads it and pops a host
#      terminal-notifier toast naming the folder. That's terminal-INDEPENDENT,
#      unlike OSC notifications, which depend on the emulator (Ghostty/Zed/...).
# Fires in the two "Claude is blocked on you" cases the host toasts cover:
# permission prompts and AskUserQuestion options.
#
# Wired by create-worktree.sh into ~/.claude/settings.json (see vm/claude-hooks.json):
#   Notification               -> claude-bell.sh notification  (only permission_prompt)
#   PreToolUse/AskUserQuestion -> claude-bell.sh options        (matcher already scopes it)
set -u
mode=${1:-}
payload="$(cat 2>/dev/null || true)"

case "$mode" in
    notification)
        # Only for tool-permission prompts, never the 60s idle reminder. Field is
        # `.type` in current Claude Code; older builds used `.notification_type`.
        ntype="$(printf '%s' "$payload" | jq -r '.type // .notification_type // empty' 2>/dev/null || true)"
        [ "$ntype" = "permission_prompt" ] || exit 0
        reason=permission
        ;;
    options)
        reason=options   # the AskUserQuestion matcher already scopes this hook
        ;;
    *)
        exit 0
        ;;
esac

# Drop the attention marker for the host's alert-bell hook (the folder is derived
# host-side from the worktree path). Atomic temp+rename. WORKTREE_DIR (exported
# via ~/.zulip-dev-env.sh) is the worktree root = the host SSH pane's cwd. Write
# it BEFORE the bell so it's in place by the time the bell triggers the host hook.
dir=${WORKTREE_DIR:-}
if [ -n "$dir" ] && [ -d "$dir" ]; then
    tmp="$dir/.claude-vm-attention.tmp.$$"
    if printf '%s %s\n' "$reason" "$(date +%s)" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$dir/.claude-vm-attention" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi
fi

# Ring the bell. /dev/tty is the forwarded pty; BEL is non-printing (safe in the
# fullscreen TUI). 2>/dev/null before >/dev/tty so a missing tty doesn't leak an
# error; fall back to stdout if there's no usable tty.
printf '\a' 2>/dev/null >/dev/tty || printf '\a'
