#!/usr/bin/env bash
# Container-side companion to claude-bell.sh. The container's Claude can't set
# @claude_state on the HOST tmux (no socket reachable), so instead it writes its
# working state into a file in the BIND-MOUNTED worktree dir. That dir has the
# SAME absolute path on host and container, and the host tmux pane running
# `vagrant ssh` has its cwd there — so host/bin/claude-tmux-status.sh reads
# "#{pane_current_path}/.claude-vm-state" and renders the "working" glyph.
#
# Usage (from vm/claude-hooks.json):
#   claude-vm-state.sh working   # UserPromptSubmit / PreToolUse (refreshes ts)
#   claude-vm-state.sh idle      # Stop                          (spinner off)
#   claude-vm-state.sh clear     # SessionEnd                    (remove file)
#
# File format: "<state> <epoch>". The host treats a `working` older than its
# staleness window as idle, so a crash that skips Stop/SessionEnd self-heals.
set -u
cat >/dev/null 2>&1 || true   # drain the hook's JSON payload on stdin
state=${1:-}

# WORKTREE_DIR (exported via ~/.zulip-dev-env.sh) is the worktree root = the
# host SSH pane's cwd. Without it we can't place the file where the host looks.
dir=${WORKTREE_DIR:-}
[ -n "$dir" ] && [ -d "$dir" ] || exit 0
f="$dir/.claude-vm-state"

case "$state" in
    clear) rm -f "$f" 2>/dev/null || true; exit 0 ;;
    working|idle) ;;
    *) exit 0 ;;
esac

# Atomic write: temp + rename in the same dir, so the host never reads a
# half-written line.
tmp="$f.tmp.$$"
if printf '%s %s\n' "$state" "$(date +%s)" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
fi
exit 0
