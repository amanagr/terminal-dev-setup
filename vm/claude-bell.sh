#!/usr/bin/env bash
# Headless-container analog of the host's desktop-toast hooks. The container
# has no desktop session, so terminal-notifier / notify-send can't show a
# toast — but a terminal bell (\a) written to the controlling tty rides the
# `vagrant ssh` / VSCode pty back to your host terminal (Ghostty, VSCode), so
# it still alerts you. We ring in the same two "Claude is blocked on you"
# cases the host toasts cover: permission prompts and AskUserQuestion options.
#
# Wired by create-worktree.sh into ~/.claude/settings.json (see vm/claude-hooks.json):
#   Notification               -> claude-bell.sh notification  (rings only on permission_prompt)
#   PreToolUse/AskUserQuestion -> claude-bell.sh options        (matcher already scopes it)
set -u
mode=${1:-}
payload="$(cat 2>/dev/null || true)"

case "$mode" in
    notification)
        # Ring only for tool-permission prompts, never the 60s idle reminder.
        # Field is `.type` in current Claude Code; older builds used
        # `.notification_type` — mirror host/bin/claude-notify.sh and read both.
        # If jq is somehow absent, ntype is empty -> no ring (safe, no false bells).
        ntype="$(printf '%s' "$payload" | jq -r '.type // .notification_type // empty' 2>/dev/null || true)"
        [ "$ntype" = "permission_prompt" ] || exit 0
        ;;
    options)
        : # the AskUserQuestion matcher already scopes this hook; always ring
        ;;
    *)
        exit 0
        ;;
esac

# /dev/tty is this session's controlling terminal (the forwarded pty), so the
# BEL reaches the host terminal even though we run inside the container. BEL is
# non-printing, so it's safe even while Claude owns the fullscreen TUI. Try the
# tty, fall back to stdout if there's no usable one (e.g. headless automation).
# `2>/dev/null` is ordered BEFORE `>/dev/tty` so fd 2 is already /dev/null when
# the open fails — otherwise the shell leaks a "cannot open /dev/tty" error,
# which a hook would surface. (`[ -w /dev/tty ]` is unreliable: it can pass when
# the device exists but has no attached terminal, so just attempt the write.)
printf '\a' 2>/dev/null >/dev/tty || printf '\a'
