#!/bin/sh
# Tmux popup file picker. fd lists files in the popup's cwd, fzf narrows,
# selection opens in $EDITOR (the popup hosts the editor session, so
# quitting the editor closes the popup — same UX as the broot popup it
# replaces).
#
# fd auto-honors ~/.config/fd/ignore, keeping this picker consistent
# with Neovim's smart-open / live-grep. .git/ is always excluded.
#
# Usage:
#   tmux-fzf-find.sh           # default — honors ignore file + .gitignore,
#                              # skips dotfiles
#   tmux-fzf-find.sh hidden    # same, but also surfaces dotfiles (--hidden)
set -eu

mode="${1:-filtered}"

case "$mode" in
    hidden)
        prompt="files (incl. hidden)> "
        set -- --type f --hidden --exclude .git
        ;;
    *)
        prompt="files> "
        set -- --type f --exclude .git
        ;;
esac

sel=$(fd "$@" | fzf \
    --prompt "$prompt" \
    --height 100% \
    --layout reverse \
    --preview 'bat --color=always --style=plain {} 2>/dev/null || cat {}' \
    --preview-window 'right,60%') || exit 0

[ -n "$sel" ] || exit 0
exec "${EDITOR:-nvim}" "$sel"
