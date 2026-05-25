#!/usr/bin/env bash
# Smooth (~10 fps) animator for the Claude "working" tab glyph.
#
# tmux can't animate faster than 1 fps on its own: status-interval floors at
# 1s and #() output is throttled to one update per second. So while any pane
# is working, this daemon loops at ~10 fps, writes the current sparkle frame
# into each working window's @claude_anim window-option, and refreshes every
# client. window-status-format reads @claude_anim via #{E:...} (synchronous,
# no #() throttle); non-working windows keep @claude_anim cleared so their
# format falls back to the #() claude-tmux-status.sh render (permission /
# done / process-icon — all static, so 1 fps there is fine).
#
# Launched detached by claude-tmux-state.sh on any `working` event; a single
# instance is enforced with a mkdir lock (portable — flock is Linux-only).
# Self-terminating: exits when no pane is working or no client is attached.
set -u
command -v tmux >/dev/null 2>&1 || exit 0

lockdir="${TMPDIR:-/tmp}/claude-spinner.lock"
if ! mkdir "$lockdir" 2>/dev/null; then
    # Reclaim a stale lock left by a hard-killed daemon (recorded pid gone).
    if [ -r "$lockdir/pid" ] && ! kill -0 "$(cat "$lockdir/pid" 2>/dev/null)" 2>/dev/null; then
        rm -rf "$lockdir" 2>/dev/null || true
        mkdir "$lockdir" 2>/dev/null || exit 0
    else
        exit 0   # a live daemon already owns the animation
    fi
fi
echo "$$" > "$lockdir/pid" 2>/dev/null || true

cleanup() {
    # Drop every @claude_anim we set so tabs fall back to the static render.
    tmux list-windows -a -F '#{window_id}' 2>/dev/null | while IFS= read -r w; do
        tmux set-option -w -u -t "$w" @claude_anim 2>/dev/null || true
    done
    # Only drop the lock if we still own it — never delete a successor's.
    if [ "$(cat "$lockdir/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$lockdir" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Sparkle bloom: shimmer opening into an asterisk at peak brightness. Keep in
# sync with the 1-fps fallback in claude-tmux-status.sh.
glyphs=(󰰥 󰰥 󰸐 󰰥)
hues=('#a371f7' '#bc8cff' '#d2b3ff' '#bc8cff')
nf=${#glyphs[@]}

i=0
prev=""
while :; do
    # Yield if a newer instance has taken the lock (defensive against dups).
    [ "$(cat "$lockdir/pid" 2>/dev/null)" = "$$" ] || break
    # Nothing to animate if no client is attached ...
    tmux list-clients -F '#{client_tty}' 2>/dev/null | grep -q . || break
    # ... or if no pane is working anywhere.
    cur=$(tmux list-panes -a -F '#{window_id} #{@claude_state}' 2>/dev/null \
        | awk '$2=="working"{print $1}' | sort -u)
    [ -n "$cur" ] || break

    frame="#[fg=${hues[$((i % nf))]}]${glyphs[$((i % nf))]} #[default]"
    printf '%s\n' "$cur" | while IFS= read -r w; do
        [ -n "$w" ] && tmux set-option -w -t "$w" @claude_anim "$frame" 2>/dev/null || true
    done

    # Windows that stopped working since last tick: clear their frame so the
    # static render (done bell / permission / process icon) takes over again.
    if [ -n "$prev" ]; then
        comm -23 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur") 2>/dev/null \
            | while IFS= read -r w; do
                  [ -n "$w" ] && tmux set-option -w -u -t "$w" @claude_anim 2>/dev/null || true
              done
    fi
    prev="$cur"

    tmux list-clients -F '#{client_tty}' 2>/dev/null | while IFS= read -r tty; do
        [ -n "$tty" ] && tmux refresh-client -S -t "$tty" 2>/dev/null || true
    done

    i=$(( (i + 1) % (nf * 64) ))
    sleep 0.1
done
