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

    # Only install if not present or version < 0.12
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
# 4. tree-sitter-cli (required by nvim-treesitter for parser compilation)
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
# 5. npm packages (claude-remote-approver)
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
# 6. Oh My Zsh
# =============================================================================
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh installed"
else
    ok "Oh My Zsh already installed"
fi

# =============================================================================
# 7. TPM (tmux plugin manager)
# =============================================================================
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    ok "TPM installed — run 'prefix + I' inside tmux to install plugins"
else
    ok "TPM already installed"
fi

# =============================================================================
# 8. Git config
# =============================================================================
info "Configuring git..."

# Pager: delta with side-by-side and line numbers
git config --global core.pager "delta"
git config --global delta.side-by-side true
git config --global delta.line-numbers true

# Diff: colorMoved for detecting renamed code
git config --global diff.colorMoved default
git config --global diff.colorMovedWs ignore-all-space

# Difftool: nvimdiff
git config --global diff.tool nvimdiff
git config --global difftool.prompt false
git config --global difftool.nvimdiff.cmd 'nvim -d "$LOCAL" "$REMOTE"'

# Editor
git config --global core.editor nvim

# Global gitignore
git config --global core.excludesFile ~/.gitignore

ok "Git configured (delta pager, nvimdiff, colorMoved)"

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
# 9. Deploy dotfiles
# =============================================================================
info "Deploying dotfiles..."

deploy_file "$SCRIPT_DIR/tmux.conf"          "$HOME/.tmux.conf"
deploy_file "$SCRIPT_DIR/nvim/init.lua"      "$HOME/.config/nvim/init.lua"
deploy_file "$SCRIPT_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"

# Claude Code settings
if [ -f "$SCRIPT_DIR/claude-settings.json" ]; then
    deploy_file "$SCRIPT_DIR/claude-settings.json" "$HOME/.claude/settings.json"
fi

# =============================================================================
# 10. Inject shell aliases into .zshrc
# =============================================================================
MARKER_START="# >>> terminal-dev-setup >>>"
MARKER_END="# <<< terminal-dev-setup <<<"

inject_aliases() {
    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        warn ".zshrc not found — creating one"
        touch "$zshrc"
    fi

    # Remove existing block if present
    if grep -qF "$MARKER_START" "$zshrc"; then
        info "Updating existing terminal-dev-setup block in .zshrc..."
        # Create temp file without the old block
        local tmpfile
        tmpfile=$(mktemp)
        awk "
            /$MARKER_START/ { skip=1; next }
            /$MARKER_END/   { skip=0; next }
            !skip { print }
        " "$zshrc" > "$tmpfile"
        mv "$tmpfile" "$zshrc"
    fi

    # Append new block
    {
        echo ""
        echo "$MARKER_START"
        cat "$SCRIPT_DIR/zsh-aliases.zsh"
        echo "$MARKER_END"
    } >> "$zshrc"

    ok "Shell aliases injected into .zshrc"
}

backup_if_exists "$HOME/.zshrc"
inject_aliases

# =============================================================================
# 11. Set zsh as default shell (if not already)
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
echo "       git config --global user.name \"Your Name\""
echo "       git config --global user.email \"your@email.com\""
echo ""
if [ -d "$BACKUP_DIR" ]; then
    echo -e "  ${YELLOW}Backups saved to: $BACKUP_DIR${NC}"
    echo ""
fi
echo "Terminal gotchas:"
echo "  - Terminal type should be xterm-256color for proper color support"
