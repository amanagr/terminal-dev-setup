#!/usr/bin/env bash
# Tmux popup file picker. fd lists files in the popup's cwd, fzf narrows,
# selection opens in $EDITOR (the popup hosts the editor session, so
# quitting the editor closes the popup — same UX as the broot popup it
# replaces).
#
# fd auto-honors ~/.config/fd/ignore, keeping this picker consistent
# with Neovim's smart-open / live-grep. .git/ is always excluded.
#
# bash, not /bin/sh — we need `set -o pipefail` (not POSIX; dash, which
# /bin/sh resolves to on Ubuntu, rejects it with `set: Illegal option`).
#
# Usage:
#   tmux-fzf-find.sh           # default — honors ignore file + .gitignore,
#                              # skips dotfiles
#   tmux-fzf-find.sh hidden    # same, but also surfaces dotfiles (--hidden)
set -euo pipefail

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

# Two stages so fd errors and fzf-cancel are distinguishable. The
# earlier single-pipeline form `fd … | fzf … || exit 0` swallowed *both*
# (`|| exit 0` matched fzf's 130 on Esc and also matched any fd
# failure), defeating the pipefail goal.
if ! list=$(fd "$@"); then
    echo "tmux-fzf-find: fd failed" >&2
    exit 1
fi
# fzf exits 130 on Esc / Ctrl-C, 1 if no match. Both are "user quit, no
# selection" — exit cleanly so the popup just closes.
sel=$(printf '%s\n' "$list" | fzf \
    --prompt "$prompt" \
    --height 100% \
    --layout reverse \
    --preview 'bat --color=always --style=plain {} 2>/dev/null || cat {}' \
    --preview-window 'right,60%') || exit 0

[ -n "$sel" ] || exit 0
# Word-split $EDITOR so values like `code --wait` / `nvim --clean` work,
# not just bare binaries. Intentional unquoted expansion — $EDITOR is
# user-set, so word-splitting it on IFS is the documented way to honor
# editor wrappers. `--` then separates the editor's own flags from the
# filename, in case the file starts with `-`.
set -- ${EDITOR:-nvim}
exec "$@" -- "$sel"
