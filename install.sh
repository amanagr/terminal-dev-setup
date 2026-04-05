#!/usr/bin/env bash
# =============================================================================
# install.sh — Zulip dev environment setup for Ubuntu
#
# Installs tools, configures git, and deploys dotfiles with backups.
# Safe to re-run: backs up existing files, skips already-installed tools.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Backup helper ---
backup_if_exists() {
    local target="$1"
    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(basename "$target")"
        cp -rL "$target" "$backup_path" 2>/dev/null || true
        warn "Backed up $target -> $backup_path"
    fi
}

# --- Copy helper (backs up then copies) ---
deploy_file() {
    local src="$1"
    local dest="$2"
    backup_if_exists "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    ok "Deployed $dest"
}

# =============================================================================
# 1. APT packages
# =============================================================================
info "Installing apt packages..."
sudo apt-get update -qq

APT_PACKAGES=(
    tmux
    tig
    ripgrep
    fzf
    fd-find
    bat
    git-delta
    jq
    curl
    unzip
    build-essential
    zsh
    fontconfig
    xclip
)

sudo apt-get install -y "${APT_PACKAGES[@]}"
ok "APT packages installed"

# Create 'bat' symlink if only 'batcat' exists (Ubuntu names it batcat)
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    ok "Created bat -> batcat symlink"
fi

# Create 'fd' symlink if only 'fdfind' exists (Ubuntu names it fdfind)
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "Created fd -> fdfind symlink"
fi

# =============================================================================
# 2. Neovim (appimage — apt version is outdated, need 0.12+)
# =============================================================================
install_neovim() {
    local current_version=""
    if command -v nvim &>/dev/null; then
        current_version=$(nvim --version | head -1 | grep -oP 'v\K[0-9]+\.[0-9]+')
    fi

    if [ -n "$current_version" ] && [ "$(echo -e "0.12\n$current_version" | sort -V | tail -1)" = "$current_version" ]; then
        ok "Neovim $current_version already installed (>= 0.12)"
        return
    fi

    info "Installing Neovim via appimage..."
    local nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
    local nvim_dest="/usr/local/bin/nvim"

    curl -fsSL "$nvim_url" -o /tmp/nvim.appimage
    chmod +x /tmp/nvim.appimage
    sudo mv /tmp/nvim.appimage "$nvim_dest"
    ok "Neovim installed to $nvim_dest"
}
install_neovim

# =============================================================================
# 3. Lazygit (from GitHub releases)
# =============================================================================
install_lazygit() {
    if command -v lazygit &>/dev/null; then
        ok "lazygit already installed: $(lazygit --version | head -1)"
        return
    fi

    info "Installing lazygit..."
    local version
    version=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" |
              grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        err "Could not determine lazygit latest version"
        return 1
    fi

    local url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_x86_64.tar.gz"
    curl -fsSL "$url" -o /tmp/lazygit.tar.gz
    tar xzf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo mv /tmp/lazygit /usr/local/bin/lazygit
    rm -f /tmp/lazygit.tar.gz
    ok "lazygit $version installed"
}
install_lazygit

# =============================================================================
# 4. Difftastic (structural diffs — used as alternate pager in lazygit)
# =============================================================================
install_difftastic() {
    if command -v difft &>/dev/null; then
        ok "difftastic already installed"
        return
    fi

    info "Installing difftastic..."
    local version
    version=$(curl -fsSL "https://api.github.com/repos/Wilfred/difftastic/releases/latest" |
              grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        err "Could not determine difftastic latest version"
        return 1
    fi

    local url="https://github.com/Wilfred/difftastic/releases/download/${version}/difft-x86_64-unknown-linux-gnu.tar.gz"
    curl -fsSL "$url" | tar xz -C /tmp
    sudo mv /tmp/difft /usr/local/bin/difft
    ok "difftastic installed"
}
install_difftastic

# =============================================================================
# 5. tree-sitter-cli (required by nvim-treesitter for parser compilation)
# =============================================================================
install_tree_sitter_cli() {
    if command -v tree-sitter &>/dev/null; then
        ok "tree-sitter-cli already installed: $(tree-sitter --version 2>/dev/null || echo 'unknown')"
        return
    fi

    info "Installing tree-sitter-cli..."
    local version
    version=$(curl -fsSL "https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest" |
              grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        warn "Could not determine tree-sitter-cli version, trying npm fallback..."
        if command -v npm &>/dev/null; then
            sudo npm install -g tree-sitter-cli
        fi
        return
    fi

    local url="https://github.com/tree-sitter/tree-sitter/releases/download/v${version}/tree-sitter-linux-x64.gz"
    curl -fsSL "$url" | gunzip > /tmp/tree-sitter
    chmod +x /tmp/tree-sitter
    sudo mv /tmp/tree-sitter /usr/local/bin/tree-sitter
    ok "tree-sitter-cli $version installed"
}
install_tree_sitter_cli

# =============================================================================
# 5b. Broot (interactive file tree browser — used in tmux popup)
# =============================================================================
install_broot() {
    if command -v broot &>/dev/null; then
        ok "broot already installed: $(broot --version)"
        return
    fi

    info "Installing broot..."
    local url="https://dystroy.org/broot/download/x86_64-linux/broot"
    curl -fsSL "$url" -o /tmp/broot
    chmod +x /tmp/broot
    mkdir -p "$HOME/.local/bin"
    mv /tmp/broot "$HOME/.local/bin/broot"
    ok "broot installed"
}
install_broot

# =============================================================================
# 6. Starship prompt
# =============================================================================
if ! command -v starship &>/dev/null; then
    info "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    ok "Starship installed"
else
    ok "Starship already installed"
fi

# =============================================================================
# 7. JetBrains Mono Nerd Font
# =============================================================================
if ! fc-list | grep -qi "JetBrainsMono Nerd"; then
    info "Installing JetBrains Mono Nerd Font..."
    mkdir -p "$HOME/.local/share/fonts"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
        | tar xJ -C "$HOME/.local/share/fonts"
    fc-cache -f
    ok "JetBrains Mono Nerd Font installed"
else
    ok "JetBrains Mono Nerd Font already installed"
fi


# =============================================================================
# 9. npm packages (claude-remote-approver)
# =============================================================================
if command -v npm &>/dev/null; then
    info "Installing global npm packages..."
    sudo npm install -g claude-remote-approver 2>/dev/null || {
        warn "npm global install failed — you may need to configure npm prefix"
    }
    ok "npm packages installed"
else
    warn "npm not found — skipping claude-remote-approver"
    warn "Install Node.js first, then run: npm install -g claude-remote-approver"
fi

# =============================================================================
# 10. Oh My Zsh + plugins
# =============================================================================
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh installed"
else
    ok "Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    info "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    ok "zsh-autosuggestions installed"
fi

# zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    info "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    ok "zsh-syntax-highlighting installed"
fi

# =============================================================================
# 11. TPM (tmux plugin manager)
# =============================================================================
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    ok "TPM installed — run 'prefix + I' inside tmux to install plugins"
else
    ok "TPM already installed"
fi

# Catppuccin tmux theme (manual install — avoids TPM name conflicts)
CATPPUCCIN_TMUX_DIR="$HOME/.config/tmux/plugins/catppuccin"
if [ ! -d "$CATPPUCCIN_TMUX_DIR/tmux" ]; then
    info "Installing catppuccin tmux theme..."
    mkdir -p "$CATPPUCCIN_TMUX_DIR"
    git clone https://github.com/catppuccin/tmux.git "$CATPPUCCIN_TMUX_DIR/tmux"
    ok "Catppuccin tmux theme installed"
else
    ok "Catppuccin tmux theme already installed"
fi

# =============================================================================
# 12. Git config
# =============================================================================
info "Configuring git..."

# Pager: delta with side-by-side and line numbers
git config --global core.pager "delta"
git config --global delta.side-by-side true
git config --global delta.line-numbers true

# Diff
git config --global diff.tool nvimdiff
git config --global diff.colorMoved default
git config --global diff.colorMovedWs ignore-all-space
git config --global diff.algorithm histogram
git config --global difftool.prompt false
git config --global difftool.nvimdiff.cmd 'nvim -d "$LOCAL" "$REMOTE"'

# Editor
git config --global core.editor nvim
git config --global core.excludesFile ~/.gitignore

# Rebase workflow
git config --global rerere.enabled true
git config --global rebase.autosquash true
git config --global rebase.autostash true

# Merge
git config --global merge.conflictstyle zdiff3

# Push/pull/fetch
git config --global pull.rebase true
git config --global push.autoSetupRemote true
git config --global fetch.prune true

# Misc
git config --global commit.verbose true
git config --global branch.sort -committerdate
git config --global init.defaultBranch main

# Aliases
git config --global alias.fixup "commit --fixup"
git config --global alias.amend "commit --amend --no-edit"
git config --global alias.uncommit "reset --soft HEAD~1"
git config --global alias.dw "diff --word-diff"
git config --global alias.recent "branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)'"

ok "Git configured"

# Prompt for user identity if not set
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    warn "Git user.name not set. Set it with:"
    warn "  git config --global user.name \"Your Name\""
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    warn "Git user.email not set. Set it with:"
    warn "  git config --global user.email \"your@email.com\""
fi

# =============================================================================
# 13. Deploy dotfiles
# =============================================================================
info "Deploying dotfiles..."

deploy_file "$SCRIPT_DIR/tmux.conf"          "$HOME/.tmux.conf"
deploy_file "$SCRIPT_DIR/nvim/init.lua"      "$HOME/.config/nvim/init.lua"
deploy_file "$SCRIPT_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"
deploy_file "$SCRIPT_DIR/starship.toml"      "$HOME/.config/starship.toml"

# Claude Code settings
if [ -f "$SCRIPT_DIR/claude-settings.json" ]; then
    deploy_file "$SCRIPT_DIR/claude-settings.json" "$HOME/.claude/settings.json"
fi

# =============================================================================
# 14. Configure .zshrc
# =============================================================================
configure_zshrc() {
    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        warn ".zshrc not found — creating one"
        touch "$zshrc"
    fi

    backup_if_exists "$zshrc"

    # Remove old marker-based block if present (migration from previous version)
    if grep -qF "# >>> terminal-dev-setup >>>" "$zshrc"; then
        info "Removing old marker-based alias block from .zshrc..."
        local tmpfile
        tmpfile=$(mktemp)
        awk '
            /# >>> terminal-dev-setup >>>/ { skip=1; next }
            /# <<< terminal-dev-setup <<</ { skip=0; next }
            !skip { print }
        ' "$zshrc" > "$tmpfile"
        mv "$tmpfile" "$zshrc"
    fi

    # Set ZSH_THEME="" (starship replaces the prompt)
    if grep -q '^ZSH_THEME=' "$zshrc"; then
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
        ok "Set ZSH_THEME=\"\" in .zshrc (starship handles the prompt)"
    fi

    # Update plugins line to include autosuggestions and syntax-highlighting
    if grep -q '^plugins=' "$zshrc"; then
        sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc"
        ok "Updated plugins in .zshrc"
    fi

    # Deploy aliases file
    deploy_file "$SCRIPT_DIR/zsh-aliases.zsh" "$HOME/.config/terminal-dev-setup/aliases.zsh"

    # Add source line (idempotent)
    local source_line='[ -r "$HOME/.config/terminal-dev-setup/aliases.zsh" ] && source "$HOME/.config/terminal-dev-setup/aliases.zsh"'
    if ! grep -qF "terminal-dev-setup/aliases.zsh" "$zshrc"; then
        echo "" >> "$zshrc"
        echo "$source_line" >> "$zshrc"
        ok "Added source line to .zshrc"
    else
        ok "Source line already in .zshrc"
    fi
}

configure_zshrc

# =============================================================================
# 15. Set zsh as default shell (if not already)
# =============================================================================
if [ "$SHELL" != "$(command -v zsh)" ]; then
    info "Setting zsh as default shell..."
    chsh -s "$(command -v zsh)" || warn "Could not change shell — run: chsh -s $(command -v zsh)"
fi

# =============================================================================
# Done
# =============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Start a new shell or run: exec zsh"
echo "  2. Open tmux and press prefix + I to install tmux plugins"
echo "  3. Open nvim — lazy.nvim will auto-install plugins on first launch"
echo "  4. Set git identity if not already configured:"
echo "       git config --global user.name \"Aman Agrawal\""
echo "       git config --global user.email \"amanagr@zulip.com\""
echo "  5. Add machine-specific config to ~/.zshrc.local (optional)"
echo ""
if [ -d "$BACKUP_DIR" ]; then
    echo -e "  ${YELLOW}Backups saved to: $BACKUP_DIR${NC}"
    echo ""
fi
