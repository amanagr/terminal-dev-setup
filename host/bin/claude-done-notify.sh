#!/usr/bin/env bash
# Desktop toast when Claude finished on a pane you weren't watching and still
# hasn't been seen. Armed by claude-tmux-state.sh via `tmux run-shell -b -d 18`
# when a pane enters @claude_state=done. Fires only if the pane is STILL `done`
# ~18s later — a visit flips it to done_seen, a reply flips it to working, and
# either makes this a silent no-op. So coming back (or replying) cancels it.
set -u
pane=${1:-}
[ -n "$pane" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

[ "$(tmux show-options -pqv -t "$pane" @claude_state 2>/dev/null || true)" = done ] || exit 0

# Strip " and \ so an odd window name can't break the osascript string below
# (the only branch that embeds it in a sub-language).
where=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_name}' 2>/dev/null | tr -d '"\\')
title="Claude finished"
msg="Your turn${where:+ — $where}"

# Same notifier chain as claude-notify.sh: terminal-notifier, then notify-send
# (Linux), then osascript (macOS fallback). -group coalesces repeats.
if command -v terminal-notifier >/dev/null 2>&1; then
    exec terminal-notifier -group claude-done -title "$title" -message "$msg" -sound default
elif command -v notify-send >/dev/null 2>&1; then
    exec notify-send "$title" "$msg"
elif command -v osascript >/dev/null 2>&1; then
    # Glass is a real /System/Library/Sounds file; "default" isn't (would be silent).
    exec osascript -e "display notification \"$msg\" with title \"$title\" sound name \"Glass\""
fi
exit 0
