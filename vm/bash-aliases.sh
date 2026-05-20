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
    git rev-parse --verify --quiet "$base" >/dev/null \
        || { echo "gdiverg: '$base' is not a known ref" >&2; return 1; }
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
# `--interface=` (empty) is defensive: run-dev already defaults to bind-all
# when the OS user is `vagrant` (see run-dev:92-104), but the explicit form
# is robust against upstream changes. See vm/CLAUDE.md.
alias run='./tools/run-dev --interface='

zlint() {
    : "${WORKTREE_DIR:?set WORKTREE_DIR or source ~/.zulip-dev-env.sh first}"
    ( cd "$WORKTREE_DIR" && ./tools/lint --modified )
}

# Cherry-pick the local Zulip HMR fix onto the current branch — enables
# webpack hot-reload on non-9991 worktrees. The patch lives on branch
# `fix-webpack-client-port-for-non-default-host-port` in the shared .git
# common dir (added by ../bin/create-worktree.sh setup); see vm/CLAUDE.md
# §"Webpack HMR on non-9991 worktrees" for the rationale. Remove once
# the change lands upstream.
#
# Guards: must be in a git worktree, branch ref must exist, must not be
# already in HEAD's history (avoids the sticky CHERRY_PICK_HEAD state from
# cherry-picking an already-merged commit).
live-update() {
    local ref=fix-webpack-client-port-for-non-default-host-port
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || { echo "live-update: not in a git repo" >&2; return 1; }
    git rev-parse --verify --quiet "$ref" >/dev/null \
        || { echo "live-update: branch '$ref' missing; see vm/CLAUDE.md §Webpack HMR" >&2; return 1; }
    if git merge-base --is-ancestor "$ref" HEAD; then
        echo "live-update: already in HEAD's history, nothing to do"
        return 0
    fi
    git cherry-pick "$ref" || {
        echo "live-update: cherry-pick conflicted — \`git cherry-pick --abort\` to bail, or resolve + \`git cherry-pick --continue\`" >&2
        return 1
    }
}

# --- Paths ---
# Idempotent — re-sourcing ~/.bashrc shouldn't keep growing PATH.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
