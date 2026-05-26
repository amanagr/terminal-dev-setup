#!/usr/bin/env bash
# Host-side desktop toast for CONTAINER Claude. Wired to tmux's `alert-bell`
# hook (host/tmux.conf): when a bell fires in any window, check whether a
# container Claude just dropped an attention marker into a bind-mounted worktree
# — vm/claude-bell.sh writes "$WORKTREE_DIR/.claude-vm-attention" = "<reason>
# <epoch>" right before ringing the bell. If a FRESH one is found, pop a
# terminal-notifier toast naming the folder, then consume the marker.
#
# Why host-side instead of an OSC notification from the container: the container
# is headless (no terminal-notifier), and OSC desktop-notification sequences
# depend on the outer emulator (Ghostty supports them, Zed's alacritty-based
# terminal does not). Running terminal-notifier on the host works regardless of
# which terminal you're in, as long as the bell reaches the host tmux.
#
# Random non-Claude bells (vim, a build tool) have no fresh marker, so they
# don't toast. The folder is the worktree dir basename; grouped per folder so
# different checkouts don't replace each other.
set -u
command -v tmux >/dev/null 2>&1 || exit 0
command -v terminal-notifier >/dev/null 2>&1 || exit 0   # macOS host only

now=$(date +%s)
# Dedupe worktree paths across all panes (a pane's cwd == the bind-mount root),
# and toast for any with a fresh attention marker. Runs only on bell events.
tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null | sort -u | while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    f="$dir/.claude-vm-attention"
    [ -f "$f" ] || continue
    IFS=' ' read -r reason ts < "$f" 2>/dev/null || { rm -f "$f" 2>/dev/null; continue; }
    case "$ts" in ''|*[!0-9]*) rm -f "$f" 2>/dev/null; continue ;; esac
    # Stale marker (>15s) — the bell that goes with it already passed; drop it.
    [ "$(( now - ts ))" -lt 15 ] || { rm -f "$f" 2>/dev/null; continue; }
    rm -f "$f" 2>/dev/null   # consume so the next unrelated bell won't re-toast
    folder=$(basename "$dir")
    case "$reason" in
        permission) msg="Needs your permission" ;;
        options)    msg="Has options for you to choose" ;;
        *)          msg="Needs your attention" ;;
    esac
    terminal-notifier -group "claude-$folder" -title "Claude — $folder" \
        -message "$msg" -sound default >/dev/null 2>&1 || true
done
exit 0
