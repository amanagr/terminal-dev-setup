#!/usr/bin/env bash
# Called from Claude Code's `Notification` hook (~/.claude/settings.json).
#
# Claude fires this event in two cases: (1) it needs permission to run a
# tool, and (2) the prompt has been idle for ≥60 s. We only want the
# desktop popup in case (1) — the idle reminder is noisy when you're
# deliberately context-switched away. Match on the literal "permission"
# substring in the JSON payload Claude streams on stdin.
set -euo pipefail
payload="$(cat)"
case "$payload" in
    *permission*) ;;          # permission request — fall through to notify
    *)            exit 0 ;;   # idle reminder (or anything else) — stay silent
esac
exec notify-send -u normal -i dialog-information "Claude" "Needs your permission"
