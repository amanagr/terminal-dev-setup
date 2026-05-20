# =============================================================================
# terminal-dev-setup VM aliases — sourced from ~/.bashrc.
# Slim bash port of host/zsh-aliases.zsh: only the bits that make sense
# inside a headless Vagrant+Docker container (git, editor, zulip helpers).
# No tmux, starship, fzf, transmission, ghostty, pdf — those are host-only.
# =============================================================================

# --- Editor ---
alias v='vim'
alias vi='vim'

# --- Git shortcuts ---
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline -20'
alias gla='git log --oneline --all --graph -30'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcp='git cherry-pick'
alias grb='git rebase'
alias grbi='git rebase -i'
alias gst='git stash'
alias gstp='git stash pop'

# Show diff for a specific commit, piped through delta when present.
gshow() {
    if command -v delta >/dev/null 2>&1; then
        git show "${1:-HEAD}" | delta
    else
        git show "${1:-HEAD}"
    fi
}

# Git log with file changes.
glf() { git log --oneline --stat -"${1:-10}"; }

# Search git log messages.
gls() { git log --oneline --all --grep="$1"; }

# Search code across git history (pickaxe).
ggrep() { git log --oneline -S "$1" -- "${2:-.}"; }

# Fixup a commit and auto-squash it in one step.
gfix() {
    git commit --fixup="$1" \
        && GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$1"~1
}

# Show divergence from a base branch.
gdiverg() {
    local base="${1:-upstream/main}"
    echo "Commits ahead of $base:"
    git log --oneline "$base"..HEAD
    printf '\nCommits behind %s:\n' "$base"
    git log --oneline HEAD.."$base"
}

# --- Better defaults ---
alias ll='ls -alh --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Ubuntu's bat package installs the binary as `batcat` to avoid colliding
# with the unrelated `bat(1)` from bacula; prefer either name if present.
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never'
elif command -v batcat >/dev/null 2>&1; then
    alias cat='batcat --paging=never'
fi

# --- Zulip helpers ---
# $WORKTREE_DIR is exported by ~/.zulip-dev-env.sh (written by
# create-worktree.sh) and points at /Users/<you>/work/<worktree-name>.
# Zulip's Vagrantfile bind-mounts the worktree at the same Mac path
# inside the container, so this absolute Mac path resolves directly.
if [ -n "${WORKTREE_DIR:-}" ]; then
    alias zcd='cd "$WORKTREE_DIR"'
fi
# `--interface=` (empty) is required: without it, run-dev binds 127.0.0.1
# inside the container and Vagrant's host port forward can't reach it.
# See vm/CLAUDE.md.
alias run='./tools/run-dev --interface='

zlint() {
    ( cd "${WORKTREE_DIR:-.}" && ./tools/lint --modified )
}

# --- Paths ---
export PATH="$HOME/.local/bin:$PATH"
