# host/ — PopOS dev configs

These files configure the local PopOS machine: tmux, zsh + oh-my-zsh, Starship,
Ghostty, full Neovim (LSP / telescope / treesitter), and Claude with the
tmux-state-tracking hooks that drive the pulsing-dot status glyph.

## Deploy paths

| Repo file | Live path |
| --------- | --------- |
| `tmux.conf` | `~/.tmux.conf` |
| `starship.toml` | `~/.config/starship.toml` |
| `zsh-aliases.zsh` | `~/.config/terminal-dev-setup/aliases.zsh` |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `nvim/picker-ignore` | `~/.config/fd/ignore` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `claude-settings.json` | `~/.claude/settings.json` |
| `bin/claude-tmux-state.sh` | `~/.local/bin/claude-tmux-state.sh` *(chmod +x)* |
| `bin/claude-tmux-status.sh` | `~/.local/bin/claude-tmux-status.sh` *(chmod +x)* |
| `bin/claude-idle-watchdog.sh` | `~/.local/bin/claude-idle-watchdog.sh` *(chmod +x)* |
| `bin/claude-notify.sh` | `~/.local/bin/claude-notify.sh` *(chmod +x)* |
| `bin/tmux-fzf-find.sh` | `~/.local/bin/tmux-fzf-find.sh` *(chmod +x)* |

`claude-notify.sh` filters Claude's `Notification` hook so a desktop
toast pops only when Claude needs permission for a tool, not when it's
emitting the 60-second idle reminder.

## Dependencies

apt: `tmux tig ripgrep fzf bat git-delta build-essential nodejs npm wl-clipboard libnotify-bin fontconfig zsh`

User-local (no sudo):
- **Neovim ≥ 0.12** from the [official tarball](https://github.com/neovim/neovim/releases/latest) (apt's Neovim lags behind what the config needs)
- **JetBrainsMono Nerd Font** from [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases/latest) — Ghostty's `font-family` calls for `JetBrainsMono Nerd Font Mono` (the **Mono** variant; single-cell glyphs keep statusline borders straight)
- **oh-my-zsh** + the `zsh-autosuggestions` and `zsh-syntax-highlighting` custom plugins
- **Starship** prompt (`curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir ~/.local/bin --yes`)
- **TPM** for tmux plugins: `git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm`, then `prefix + I` inside tmux
- **tree-sitter CLI** (needed by nvim-treesitter ≥ 0.12 to compile parsers): `npm install --prefix ~/.local -g tree-sitter-cli`
- **Ruff** (Python linter / LSP): `curl -LsSf https://astral.sh/ruff/install.sh | sh` — Mason's PyPI installer needs pip/pipx so we install the standalone binary

System .deb (no upstream package — community .deb is the cleanest path on Ubuntu 24.04):
- **Ghostty**: download the matching `ghostty_*_amd64_24.04.deb` from [mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu/releases/latest), `sudo dpkg -i` it, then `sudo apt-get install -fy`

## After deploy

- `chsh -s /usr/bin/zsh` — make zsh the login shell.
- Inside tmux: `prefix + I` (capital I) to fetch the plugins listed at the
  bottom of `tmux.conf`.
- First nvim launch downloads + compiles all treesitter parsers and Mason
  language servers; let it sit for ~30 s, then `:Lazy sync` to confirm clean.

## Hardware quirks

### WiFi drops after a brief period of working (MT7921e)

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
