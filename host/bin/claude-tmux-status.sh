#!/usr/bin/env bash
# Renders a per-process glyph in the tmux window-status-format.
#
# Usage: claude-tmux-status.sh <window_id> [active|inactive]
#
# Picks the active pane's current command and maps it to a glyph in
# the process's brand color (git orange, docker blue, rust orange,
# go cyan, ...). For claude panes the glyph is state-aware, driven
# by @claude_state (set by claude-tmux-state.sh):
#   working    → pulsing braille spinner cycling through purple shades
#   permission → ⚠ in warning yellow
#   idle / *   → no glyph (the pane itself signals "claude is here")
#
# Inactive tabs render the glyph in muted gray so the rainbow of
# brand colors doesn't compete with the active-tab highlight; the
# active tab emits the full brand color on its surface bg. Claude
# state glyphs always keep their own color since the color *is* the
# signal (purple pulse = working, yellow ⚠ = permission).
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
# permission > working > none. Runs *before* the process-icon switch
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
while IFS= read -r s; do
    case "$s" in
        permission) claude_state=permission; break ;;
        working)    [ "$claude_state" = permission ] || claude_state=working ;;
    esac
done < <(tmux list-panes -t "$window" -F '#{@claude_state}' 2>/dev/null)

case "$claude_state" in
    working)
        # Braille rotation (10 frames, slow clockwise sweep) +
        # purple-shade pulse (4 frames, faster). The two cycles
        # being co-prime gives a richer, less-mechanical feel.
        glyphs=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        hues=('#d2b3ff' '#bc8cff' '#a371f7' '#bc8cff')
        n=$(date +%s)
        printf '#[fg=%s]%s #[default]' \
            "${hues[$(( n % 4 ))]}" \
            "${glyphs[$(( n % 10 ))]}"
        exit 0
        ;;
    permission)
        printf '#[fg=%s]⚠ #[default]' "$warning"
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
