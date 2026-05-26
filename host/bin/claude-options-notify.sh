#!/usr/bin/env bash
# Called from Claude Code's `PreToolUse` hook, matched to the AskUserQuestion
# tool (~/.claude/settings.json). Fires a desktop toast the moment Claude is
# about to present you a multiple-choice question.
#
# Why a PreToolUse hook and not the Notification hook: AskUserQuestion does NOT
# emit a Notification event. Notification only fires for `permission_prompt`,
# `idle_prompt`, `auth_success`, and the MCP `elicitation_*` types — so the
# only way to catch "Claude has options for you" is to intercept the tool call.
#
# Same notifier chain + stdout-swallowing as claude-notify.sh: terminal-notifier
# on macOS, notify-send on Linux, osascript as a last-resort macOS fallback.
# Silent if none is installed (no spam in CI / headless environments).
set -euo pipefail
cat >/dev/null  # drain the JSON payload on stdin; no field is needed here

title="Claude"
msg="Has options for you to choose"

if command -v terminal-notifier >/dev/null 2>&1; then
    # -group claude coalesces with the permission toast (one "needs you" toast
    # at a time). >/dev/null swallows the "Removing previously sent…" log it
    # prints on replace — otherwise it leaks into the pane via the hook.
    exec terminal-notifier -group claude -title "$title" -message "$msg" -sound default >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
    exec notify-send -u normal -i dialog-question "$title" "$msg" >/dev/null 2>&1
elif command -v osascript >/dev/null 2>&1; then
    # Glass is a real /System/Library/Sounds file; "default" isn't (would be silent).
    exec osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\"" >/dev/null 2>&1
fi
