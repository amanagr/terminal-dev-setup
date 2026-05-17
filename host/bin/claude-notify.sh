#!/usr/bin/env bash
# Called from Claude Code's `Notification` hook (~/.claude/settings.json).
#
# Claude fires this event in two cases: (1) it needs permission to run a
# tool, and (2) the prompt has been idle for ≥60 s. We only want the
# desktop popup in case (1) — the idle reminder is noisy when you're
# deliberately context-switched away.
#
# Discriminate via the typed `notification_type` field on the JSON
# payload Claude streams on stdin (value `permission_prompt` for the
# tool-permission case). A previous version did a raw substring match
# for "permission", which false-positived on any payload whose `cwd`,
# `transcript_path`, etc. contained the literal substring — e.g. a
# project at ~/code/permissions-test.
#
# Notifier is auto-detected: terminal-notifier on macOS, notify-send on
# Linux, osascript as a last-resort macOS fallback. Silent if none is
# installed (no spam in CI / headless environments).
set -euo pipefail
payload="$(cat)"

# jq -e errors on null/empty; `// empty` + grep keeps this script silent
# when the payload is missing/malformed rather than aborting the hook.
ntype="$(printf '%s' "$payload" | jq -r '.notification_type // empty' 2>/dev/null || true)"
[ "$ntype" = "permission_prompt" ] || exit 0

title="Claude"
msg="Needs your permission"

if command -v terminal-notifier >/dev/null 2>&1; then
    # -group lets a fresh prompt replace the previous one rather than stack.
    exec terminal-notifier -group claude -title "$title" -message "$msg" -sound default
elif command -v notify-send >/dev/null 2>&1; then
    exec notify-send -u normal -i dialog-information "$title" "$msg"
elif command -v osascript >/dev/null 2>&1; then
    # $title and $msg are script-internal literals; if either ever becomes
    # payload-derived, switch to a heredoc to avoid AppleScript injection.
    # AppleScript's `sound name "X"` looks for X.aiff in Library/Sounds;
    # there is NO `default.aiff` or `DefaultSoundName.aiff`, so those
    # values are silent. Glass is a real file in /System/Library/Sounds/
    # and matches the previous shipped behaviour. osascript has no
    # built-in way to read the user's system-default notification sound
    # (that's terminal-notifier-specific), so true parity with the
    # `-sound default` branch above isn't achievable from a script.
    exec osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\""
fi
