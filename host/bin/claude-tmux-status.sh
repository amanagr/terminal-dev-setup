#!/usr/bin/env bash
# Renders a per-process glyph in the tmux window-status-format.
#
# Usage: claude-tmux-status.sh <window_id> [active|inactive]
#
# Picks the active pane's current command and maps it to a glyph in
# the process's brand color (git orange, docker blue, rust orange,
# go cyan, ...). For claude panes the glyph is state-aware, driven
# by @claude_state (set by claude-tmux-state.sh):
#   working    → Claude's sparkle bloom · ✢ ✳ ✶ ✻ ✽ in Claude's logo orange
#   permission → ⚠ in warning yellow
#   done       → bright green bell: Claude finished & you haven't visited
#                the pane since (set on Stop when you weren't watching)
#   done_seen  → dim gray bell: finished and you've glanced, but haven't
#                replied yet; clears on your next prompt
#   stalled    → red error glyph: session ended mid-work (abnormal exit)
#   idle / *   → no glyph (the pane itself signals "claude is here")
#
# Inactive tabs render the glyph in muted gray so the rainbow of
# brand colors doesn't compete with the active-tab highlight; the
# active tab emits the full brand color on its surface bg. Claude
# state glyphs always keep their own color since the color *is* the
# signal (orange bloom = working, green bell = your turn, yellow ⚠ = needs you).
#
# Glyph choices follow the joshmedeski/tmux-nerd-font-window-name
# defaults (https://github.com/joshmedeski/tmux-nerd-font-window-name);
# JetBrainsMono Nerd Font is required for them to render.

set -u
window=${1:-}
mode=${2:-inactive}
[ -n "$window" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# Brand-color palette.
muted='#7d8590'
warning='#d29922'
c_claude='#bc8cff'
c_vim='#57a143'
c_shell='#7eb91b'
c_node='#3c873a'
c_python='#ffd43b'
c_git='#f05033'
c_docker='#2496ed'
c_ssh='#7d8590'
c_rust='#dea584'
c_go='#00add8'
c_ruby='#cc342d'
c_lua='#5c8dbc'
c_sys='#7eb91b'
c_db='#336791'
c_pager='#7d8590'
c_tmux='#1bb91b'
c_make='#a82e2e'
c_net='#7d8590'
c_nix='#5277c3'
c_pdf='#cc0000'
c_files='#bc8cff'

# Inactive tabs get the muted fg so brand colors don't pull the eye
# away from the active tab. Active tab uses the brand color — its
# surface bg (#21262d) has enough contrast for any of them.
emit() {
    if [ "$mode" = active ]; then
        printf '#[fg=%s]%s #[default]' "$2" "$1"
    else
        printf '#[fg=%s]%s #[default]' "$muted" "$1"
    fi
}

# Aggregate claude state across all panes in the window with priority
# permission > stalled > working > done > done_seen > none. Runs *before* the process-icon switch
# so a background claude needing attention still signals on the tab
# even when the active pane is something else, and so two claude
# panes in the same window can't mask each other's state.
#
# Keyed off @claude_state alone — NOT pane_current_command. The hook
# (claude-tmux-state.sh) only ever sets @claude_state on a real claude
# pane, resolved via a PPID walk, so its presence already means "this
# is claude". The CLI's reported command name is unreliable: on macOS
# it surfaces as the version string (e.g. "2.1.150"), not "claude", so
# the old cmd==claude gate silently hid the glyph after the Linux→mac
# move.
claude_state=
best=0
while IFS= read -r s; do
    case "$s" in
        permission) p=5 ;;
        stalled)    p=4 ;;
        working)    p=3 ;;
        done)       p=2 ;;
        done_seen)  p=1 ;;
        *)          p=0 ;;
    esac
    if [ "$p" -gt "$best" ]; then best=$p; claude_state=$s; fi
    [ "$best" = 5 ] && break
done < <(tmux list-panes -t "$window" -F '#{@claude_state}' 2>/dev/null)

# Container Claude can't set @claude_state on the host tmux (no socket). Its
# hooks instead write "$WORKTREE_DIR/.claude-vm-state" ("working <epoch>") into
# the bind-mounted worktree dir — the SAME absolute path as the SSH pane's cwd
# here. If nothing host-local outranks working, treat a FRESH vm working file
# as working. Stale (>180s) means the turn ended without a Stop or the
# container died — fall back to no glyph. (Attention is handled by monitor-bell
# off the bell the container rings, not here.)
if [ "$best" -lt 3 ]; then
    now=$(date +%s)
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        f="$dir/.claude-vm-state"
        [ -f "$f" ] || continue
        IFS=' ' read -r vmstate vmts < "$f" 2>/dev/null || continue
        [ "$vmstate" = working ] || continue
        case "$vmts" in ''|*[!0-9]*) continue ;; esac
        [ "$(( now - vmts ))" -lt 180 ] || continue
        claude_state=working; best=3; break
    done < <(tmux list-panes -t "$window" -F '#{pane_current_path}' 2>/dev/null)
fi

case "$claude_state" in
    working)
        # Claude-style sparkle bloom: a point of light grows into a
        # six-pointed star and eases back down (· ✢ ✳ ✶ ✻ ✽ and down),
        # brightening to a glowing peak as it opens — matches Claude
        # Code's own working animation. Some frames (✳ ✻ ✽) aren't in
        # JetBrains Mono NL and come from terminal font-fallback, but
        # render cleanly. Frame clock is date +%s (~1 fps fallback); the
        # daemon drives the same frames at ~5 fps on the focused window.
        # Pulsed in Claude's logo orange (#d97757), brightening to a peak.
        glyphs=(· ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢)
        hues=('#9a5a44' '#c06b4c' '#d97757' '#e88a66' '#f59d79' '#ffb491' '#f59d79' '#e88a66' '#d97757' '#c06b4c')
        n=$(date +%s)
        printf '#[fg=%s]%s #[default]' \
            "${hues[$(( n % 10 ))]}" \
            "${glyphs[$(( n % 10 ))]}"
        exit 0
        ;;
    permission)
        printf '#[fg=%s]⚠ #[default]' "$warning"
        exit 0
        ;;
    done)
        # Bright green bell = "Claude finished — your turn", on a pane you
        # weren't watching when it stopped. Static. A visit dims it to
        # done_seen (claude-pane-seen.sh, via after-select-pane/pane-focus-in).
        printf '#[fg=%s] #[default]' '#3fb950'
        exit 0
        ;;
    done_seen)
        # Dim gray bell = finished, you've glanced, but haven't replied yet.
        # Clears on your next prompt (working overwrites it).
        printf '#[fg=%s] #[default]' '#7d8590'
        exit 0
        ;;
    stalled)
        # Red error glyph: the session ended mid-work (abnormal exit).
        printf '#[fg=%s] #[default]' '#f85149'
        exit 0
        ;;
esac

# No claude attention signal — fall through to a process icon for
# whatever the *active* pane is currently running.
proc=$(tmux list-panes -t "$window" -F '#{?pane_active,0,1} #{pane_current_command}' 2>/dev/null \
    | sort -n | head -1 | awk '{print $2}')
[ -n "$proc" ] || exit 0

case "$proc" in
    claude)
        # Active is an idle claude — no glyph (the pane signals "claude
        # is here" by itself; the tab stays quiet).
        ;;
    nvim|vim|view|nv)              emit '' "$c_vim" ;;
    node|npm|yarn|pnpm|bun|deno)   emit '' "$c_node" ;;
    python|python3|ipython|py)     emit '' "$c_python" ;;
    bash|zsh|fish|sh|dash)         emit '' "$c_shell" ;;
    git|lazygit|tig|gh)            emit '' "$c_git" ;;
    docker|docker-compose|podman)  emit '' "$c_docker" ;;
    ssh|mosh)                      emit '󰣀' "$c_ssh" ;;
    cargo|rustc|rust)              emit '' "$c_rust" ;;
    go|gopls)                      emit '' "$c_go" ;;
    ruby|irb)                      emit '' "$c_ruby" ;;
    lua|luajit)                    emit '' "$c_lua" ;;
    htop|top|btop|btm)             emit '' "$c_sys" ;;
    psql|mysql|sqlite3|redis-cli)  emit '' "$c_db" ;;
    less|more|man|tail|bat)        emit '' "$c_pager" ;;
    tmux)                          emit '' "$c_tmux" ;;
    make|cmake)                    emit '' "$c_make" ;;
    curl|wget|http|httpie)         emit '' "$c_net" ;;
    nix|home-manager)              emit '' "$c_nix" ;;
    termpdf|zathura|mupdf)         emit '' "$c_pdf" ;;
    nnn|ranger|yazi|broot)         emit '' "$c_files" ;;
    *)
        ;;
esac
