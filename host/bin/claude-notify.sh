#!/usr/bin/env bash
# Called from Claude Code's `Notification` hook (~/.claude/settings.json).
#
# Claude fires this event in two cases: (1) it needs permission to run a
# tool, and (2) the prompt has been idle for ≥60 s. We only want the
# desktop popup in case (1) — the idle reminder is noisy when you're
# deliberately context-switched away. Match on the literal "permission"
# substring in the JSON payload Claude streams on stdin.
#
# Notifier is auto-detected: terminal-notifier on macOS, notify-send on
# Linux, osascript as a last-resort macOS fallback. Silent if none is
# installed (no spam in CI / headless environments).
set -euo pipefail
payload="$(cat)"
case "$payload" in
    *permission*) ;;          # permission request — fall through to notify
    *)            exit 0 ;;   # idle reminder (or anything else) — stay silent
esac

title="Claude"
msg="Needs your permission"

if command -v terminal-notifier >/dev/null 2>&1; then
    exec terminal-notifier -title "$title" -message "$msg" -sound default
elif command -v notify-send >/dev/null 2>&1; then
    exec notify-send -u normal -i dialog-information "$title" "$msg"
elif command -v osascript >/dev/null 2>&1; then
    exec osascript -e "display notification \"$msg\" with title \"$title\""
fi
