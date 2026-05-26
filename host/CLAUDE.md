# host/ — macOS dev configs

These files configure the local Mac: tmux, zsh + oh-my-zsh, Starship,
Ghostty, a **slim Neovim** (themes + lualine + handlebars syntax — kept
around as a fallback), and Claude with the tmux-state-tracking hooks
that drive the pulsing-dot status glyph.

Primary editor on the host is **VSCode** (with the Claude CLI in
VSCode's integrated terminal). Real code editing happens there — not
in this nvim config and not in the VM.

Also works on modern Linux distros (PopOS, Ubuntu 24.04+) — the few
OS-specific bits (`copy-command pbcopy`, terminal-notifier fallback chain)
are guarded.

## Deploy paths

| Repo file | Live path |
| --------- | --------- |
| `tmux.conf` | `~/.tmux.conf` |
| `starship.toml` | `~/.config/starship.toml` |
| `zsh-aliases.zsh` | `~/.config/terminal-dev-setup/aliases.zsh` |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `claude-settings.json` | `~/.claude/settings.json` |
| `bin/claude-tmux-state.sh` | `~/.local/bin/claude-tmux-state.sh` *(chmod +x)* |
| `bin/claude-tmux-status.sh` | `~/.local/bin/claude-tmux-status.sh` *(chmod +x)* |
| `bin/claude-pane-seen.sh` | `~/.local/bin/claude-pane-seen.sh` *(chmod +x)* |
| `bin/claude-spinner-daemon.sh` | `~/.local/bin/claude-spinner-daemon.sh` *(chmod +x)* |
| `bin/claude-notify.sh` | `~/.local/bin/claude-notify.sh` *(chmod +x)* |
| `bin/claude-done-notify.sh` | `~/.local/bin/claude-done-notify.sh` *(chmod +x)* |
| `bin/tmux-fzf-find.sh` | `~/.local/bin/tmux-fzf-find.sh` *(chmod +x)* |

Add one line to `~/.zshrc` so the aliases load:

```sh
[ -f ~/.config/terminal-dev-setup/aliases.zsh ] && source ~/.config/terminal-dev-setup/aliases.zsh
```

`claude-notify.sh` filters Claude's `Notification` hook so a desktop
toast pops only when Claude needs permission for a tool, not when it's
emitting the 60-second idle reminder. The notifier is auto-detected:
`terminal-notifier` first, then `notify-send` (Linux), then `osascript`
as a last-resort macOS fallback.

**First-run permission on macOS**: macOS prompts to allow notifications
from `terminal-notifier` the first time it fires. If you dismiss or deny
the prompt the script silently no-ops (terminal-notifier exits 0 even
when notifications are blocked) — re-enable under **System Settings →
Notifications → terminal-notifier**.

## Dependencies (macOS)

Install Homebrew first (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`), then:

```sh
brew install neovim starship fzf fd bat jq gh terminal-notifier ripgrep \
             git-delta tmux tree-sitter
brew install --cask ghostty font-jetbrains-mono-nerd-font
```

(`fzf`, `fd`, `ripgrep`, `bat` aren't strictly nvim deps anymore — the
host nvim is slim — but `zsh-aliases.zsh` uses them for the `fe` / `fcd`
/ `frg` fuzzy helpers, so keep them. `tree-sitter` (the CLI) IS needed
again: nvim-treesitter's `main` branch uses it to compile parsers so diff
syntax highlighting works in diffview. `sqlite` and `ruff` aren't needed
on the host; they live in the VM provision, see
[`../vm/CLAUDE.md`](../vm/CLAUDE.md).)

Then:

- **oh-my-zsh**: `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
- **oh-my-zsh plugins**: clone `zsh-autosuggestions` and `zsh-syntax-highlighting` into `${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/` (the default-substitution form is safer in a fresh shell where `$ZSH_CUSTOM` isn't set yet).
- **TPM** for tmux plugins: `git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm`, then `prefix + I` inside tmux

## Dependencies (Linux — for reference)

apt: `tmux tig ripgrep fzf bat git-delta build-essential nodejs npm wl-clipboard libnotify-bin fontconfig zsh`

User-local additions: Neovim ≥ 0.12 tarball, JetBrainsMono Nerd Font from
nerd-fonts releases, oh-my-zsh + plugins, Starship, TPM, tree-sitter CLI,
Ruff. Ghostty: install the `ghostty_*_amd64_24.04.deb` from
[mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu/releases/latest).

## After deploy

- `chsh -s /bin/zsh` (macOS already defaults to it; harmless to confirm).
- Inside tmux: `prefix + I` (capital I) to fetch the plugins listed at
  the bottom of `tmux.conf`.
- First nvim launch installs lazy.nvim and the (small) plugin set, then
  applies the github theme.

## Hardware quirks

### Linux: WiFi drops after a brief period of working (MT7921e)

**Symptom**: WiFi connects, works for a while, then dies. NetworkManager
spams `link timed out` and `association took too long`. Reboot fixes it
temporarily, then the cycle repeats.

**Cause**: MediaTek MT7922 (`mt7921e` driver) is unreliable when WiFi
powersave parks the radio. PopOS ships
`/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` with
`wifi.powersave = 3` (enabled), which trips this bug.

**Fix** — disable WiFi powersave and silence the noisy USB-Ethernet
auto-connect:

```bash
sudo sed -i 's/^wifi.powersave = 3$/wifi.powersave = 2/' \
  /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
sudo systemctl restart NetworkManager
nmcli c modify "Wired connection 1" connection.autoconnect no
```

If the drop persists, add the deeper-level mitigation — disable PCIe
ASPM for `mt7921e`:

```bash
echo "options mt7921e disable_aspm=1" | sudo tee /etc/modprobe.d/mt7921e.conf
sudo modprobe -r mt7921e mt7921_common mt76_connac_lib mt76 && sudo modprobe mt7921e
```
