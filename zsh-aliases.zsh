# =============================================================================
# terminal-dev-setup aliases — sourced from .zshrc
# Machine-specific overrides go in ~/.zshrc.local
# =============================================================================

# --- Starship prompt ---
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# --- tmux shortcuts ---
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tn='tmux new-session -s'
alias tk='tmux kill-session -t'

# Auto-attach to 'dev' session or create it
dev() {
    tmux attach -t dev 2>/dev/null || tmux new-session -s dev
}

# --- Editor ---
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

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

# Show diff for a specific commit
gshow() {
    git show "${1:-HEAD}" | delta
}

# Git log with file changes
glf() {
    git log --oneline --stat -${1:-10}
}

# Search git log messages
gls() {
    git log --oneline --all --grep="$1"
}

# Search code across git history
ggrep() {
    git log --oneline -S "$1" -- "${2:-.}"
}

# Fixup a commit and auto-squash it in one step
gfix() {
    git commit --fixup="$1" && GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$1"~1
}

# Show divergence from a base branch
gdiverg() {
    local base="${1:-upstream/main}"
    echo "Commits ahead of $base:"
    git log --oneline "$base"..HEAD
    echo "\nCommits behind $base:"
    git log --oneline HEAD.."$base"
}

# --- lazygit ---
alias lg='lazygit'

# --- Better defaults ---
alias ll='ls -alh --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Use bat for cat if available
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
fi

# --- Fuzzy finding (fzf) ---
# Ctrl-T: fuzzy find files, Ctrl-R: fuzzy history
if command -v fzf &>/dev/null; then
    eval "$(fzf --zsh 2>/dev/null)" || source /usr/share/doc/fzf/examples/key-bindings.zsh 2>/dev/null

    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

    # Open file in nvim via fzf
    fe() {
        local file
        file=$(fzf --preview 'bat --color=always --line-range :50 {}' --preview-window=right:50%)
        [ -n "$file" ] && nvim "$file"
    }

    # cd to directory via fzf
    fcd() {
        local dir
        dir=$(fd --type d --hidden --follow --exclude .git | fzf --preview 'ls -la {}')
        [ -n "$dir" ] && cd "$dir"
    }

    # Search content and open in nvim at the line
    frg() {
        local result
        result=$(rg --line-number --no-heading --color=always "${1:-}" |
            fzf --ansi --delimiter : \
                --preview 'bat --color=always --highlight-line {2} {1}' \
                --preview-window=right:50%)
        if [ -n "$result" ]; then
            local file=$(echo "$result" | cut -d: -f1)
            local line=$(echo "$result" | cut -d: -f2)
            nvim "+$line" "$file"
        fi
    }
fi

# --- Zulip-specific helpers ---
alias zcd='cd ~/zulip'
alias run='./tools/run-dev interface=""'

zlint() {
    cd ~/zulip && ./tools/lint --modified
}

# --- Paths ---
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export PATH="$(npm prefix -g 2>/dev/null)/bin:$PATH"

# Set tmux window name to current directory
if [ -n "$TMUX" ]; then
    _tmux_rename_window() { tmux rename-window "$(basename "$PWD")"; }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _tmux_rename_window
fi

# Machine-specific overrides
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
