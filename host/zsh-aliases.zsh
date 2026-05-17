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

# Auto-attach to 'dev' session or create it. Inside tmux, switch-client
# instead of attach to avoid the "sessions should be nested with care"
# refusal.
_tmux_goto() {
    local name="$1"
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$name" 2>/dev/null \
            || { tmux new-session -d -s "$name" && tmux switch-client -t "$name"; }
    else
        tmux attach -t "$name" 2>/dev/null || tmux new-session -s "$name"
    fi
}
dev() { _tmux_goto dev; }
ops() { _tmux_goto ops; }

# --- Editor ---
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# --- PDF reader (terminal, graphical pages via Kitty graphics protocol) ---
# termpdf-rs is our Rust replacement for the now-removed termpdf.py.
# Renders pages as Kitty-graphics images inside Ghostty. Built from
# ~/termpdf-rs (see that repo's setup.sh + cargo build --release).
alias pdf='~/termpdf-rs/target/release/termpdf'

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
    eval "$(fzf --zsh 2>/dev/null)"

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

# --- transmission (BitTorrent daemon over localhost RPC) ---
# Linux-only on this setup — guarded so missing transmission-remote on
# Mac doesn't leave the aliases pointing at "command not found". `tadd`
# uses a host-side `torrent-add` script (magnet:// handler); skip it if
# absent.
if command -v transmission-remote >/dev/null 2>&1; then
    command -v torrent-add >/dev/null 2>&1 && alias tadd='torrent-add'
    alias tlist='transmission-remote -l'
    alias tdone='transmission-remote -t all -r'         # remove finished (keeps data)
    alias tstop='transmission-remote -t all -S'         # stop all
    alias tstart='transmission-remote -t all -s'        # start all
    alias tinfo='transmission-remote -t'                # tinfo <id> for details
fi

# --- Zulip-specific helpers ---
# Zulip lives under ~/work/<name> on this setup (see bin/create-worktree.sh).
# Double-quoted aliases so $HOME expands at definition time — a single-
# quoted tilde isn't expanded as a command word (only `cd`-style builtins
# re-expand it on the argument side).
alias zcd="cd $HOME/work/zulip"
alias stripe="cd $HOME/zulip-stripe/var/stripe"
alias run='./tools/run-dev'
alias z="$HOME/terminal-dev-setup/bin/create-worktree.sh"

zlint() {
    ( cd "$HOME/work/zulip" && ./tools/lint --modified )
}

# --- Paths ---
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
# Only prepend npm's global bin if npm is installed — otherwise an empty
# `$(npm prefix -g)` yields a stray /bin entry. `npm config get prefix`
# is preferred over the deprecated `npm prefix -g`.
if command -v npm >/dev/null 2>&1; then
    export PATH="$(npm config get prefix 2>/dev/null)/bin:$PATH"
fi

# Set tmux window name to current directory. ${PWD:t} (zsh tail-modifier)
# avoids forking `basename` on every prompt.
if [ -n "$TMUX" ]; then
    _tmux_rename_window() { tmux rename-window "${PWD:t}"; }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _tmux_rename_window
fi

# Machine-specific overrides
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
