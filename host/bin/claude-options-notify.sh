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
payload="$(cat 2>/dev/null || true)"  # PreToolUse payload — read for .cwd

# Include the project folder (basename of cwd) so you can tell which checkout
# is asking when several are running; group per folder so they don't replace
# each other across checkouts.
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
folder=${cwd:+$(basename "$cwd")}
title="Claude${folder:+ — $folder}"
msg="Has options for you to choose"
group="claude${folder:+-$folder}"

if command -v terminal-notifier >/dev/null 2>&1; then
    # -group (per folder) coalesces repeats for one checkout. >/dev/null swallows
    # the "Removing previously sent…" log it prints on replace — otherwise it
    # leaks into the pane via the hook.
    exec terminal-notifier -group "$group" -title "$title" -message "$msg" -sound default >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
    exec notify-send -u normal -i dialog-question "$title" "$msg" >/dev/null 2>&1
elif command -v osascript >/dev/null 2>&1; then
    # Glass is a real /System/Library/Sounds file; "default" isn't (would be silent).
    exec osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\"" >/dev/null 2>&1
fi
