#!/usr/bin/env bash
# Lightweight animator for the Claude "working" tab glyph.
#
# tmux can't animate faster than 1 fps on its own (#() output is throttled to
# one update/sec), so the frame is written into the window-option @claude_anim
# which window-status-format reads via #{E:...} (no throttle).
#
# CPU discipline (an earlier 10 fps, every-working-window version ran a laptop
# hot): this animates ONLY the single window the focused client is currently
# looking at, at ~5 fps. The moment you look away (different window, or the
# terminal loses OS focus) it stops animating and drops to a cheap 1 s poll;
# when no pane is working anywhere, it exits. Background working windows just
# use the 1 fps #() fallback in claude-tmux-status.sh.
#
# Launched detached by claude-tmux-state.sh on a working event. Single instance
# via a portable mkdir lock (flock is Linux-only) with stale-lock reclaim, an
# ownership-yield guard, and an owner-checked cleanup. SIGTERM/INT exit cleanly.
set -u
command -v tmux >/dev/null 2>&1 || exit 0

delay=0.2                       # ~5 fps while you're watching a working window

lockdir="${TMPDIR:-/tmp}/claude-spinner.lock"
if ! mkdir "$lockdir" 2>/dev/null; then
    if [ -r "$lockdir/pid" ] && ! kill -0 "$(cat "$lockdir/pid" 2>/dev/null)" 2>/dev/null; then
        rm -rf "$lockdir" 2>/dev/null || true
        mkdir "$lockdir" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
echo "$$" > "$lockdir/pid" 2>/dev/null || true

animated_win=""
cleanup() {
    [ -n "$animated_win" ] && tmux set-option -w -u -t "$animated_win" @claude_anim 2>/dev/null || true
    if [ "$(cat "$lockdir/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$lockdir" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM          # ensure SIGTERM actually terminates (-> EXIT trap)

# Claude-style sparkle bloom: a point of light grows into a six-pointed star
# and eases back (· ✢ ✳ ✶ ✻ ✽ and down), pulsed in Claude's logo orange
# (#d97757) and brightening to a glowing peak. Stay in sync with the
# claude-tmux-status.sh fallback.
glyphs=(· ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢)
hues=('#9a5a44' '#c06b4c' '#d97757' '#e88a66' '#f59d79' '#ffb491' '#f59d79' '#e88a66' '#d97757' '#c06b4c')
nf=${#glyphs[@]}
i=0

while :; do
    # Yield if a newer instance took the lock.
    [ "$(cat "$lockdir/pid" 2>/dev/null)" = "$$" ] || break

    # The window the OS-focused client is looking at, and its tty (one query).
    # Empty when no client is focused (terminal in the background).
    read -r fwin ftty < <(tmux list-clients -F '#{client_flags}|#{window_id}|#{client_tty}' 2>/dev/null \
        | awk -F'|' '/focused/{print $2, $3; exit}')

    fworking=0
    if [ -n "${fwin:-}" ]; then
        tmux list-panes -t "$fwin" -F '#{@claude_state}' 2>/dev/null | grep -qx working && fworking=1
    fi

    if [ "$fworking" = 1 ]; then
        # Animate the focused, working window only.
        if [ -n "$animated_win" ] && [ "$animated_win" != "$fwin" ]; then
            tmux set-option -w -u -t "$animated_win" @claude_anim 2>/dev/null || true
        fi
        animated_win="$fwin"
        tmux set-option -w -t "$fwin" @claude_anim \
            "#[fg=${hues[$((i % nf))]}]${glyphs[$((i % nf))]} #[default]" 2>/dev/null || true
        [ -n "${ftty:-}" ] && tmux refresh-client -S -t "$ftty" 2>/dev/null || true
        i=$(( (i + 1) % (nf * 64) ))
        sleep "$delay"
    else
        # Not looking at a working window: stop animating, then either exit
        # (nothing working anywhere) or poll slowly (work continues elsewhere).
        if [ -n "$animated_win" ]; then
            tmux set-option -w -u -t "$animated_win" @claude_anim 2>/dev/null || true
            animated_win=""
            [ -n "${ftty:-}" ] && tmux refresh-client -S -t "$ftty" 2>/dev/null || true
        fi
        anywork=$(tmux list-panes -a -F '#{@claude_state}' 2>/dev/null | grep -cx working || true)
        [ "${anywork:-0}" -gt 0 ] || break
        sleep 1
    fi
done
