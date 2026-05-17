# vm/ — Ubuntu-in-OrbStack dev VM

Files in this directory are shipped into each OrbStack Linux machine that
`bin/create-worktree.sh` provisions. The VM runs Zulip's dev server +
Claude; Neovim editing happens on the host.

## Contents

| File | Deployed inside the VM at |
| ---- | ------------------------- |
| `claude-settings.json` | `~/.claude/settings.json` |
| `nvim/init.lua`        | `~/.config/nvim/init.lua` *(optional — see below)* |

## Using the VM

| What | How |
| ---- | --- |
| Attach (shell as your Mac user) | `orb -m <name>` |
| Detach | `exit` or `Ctrl-D` |
| Run dev server (inside VM) | `cd ~/work/<name> && ./tools/run-dev --interface=''` — serves http://&lt;name&gt;.orb.local:9991. The empty `--interface` is required — without it, run-dev binds only to 127.0.0.1 inside the VM and the `<name>.orb.local` address (a separate VM interface) is unreachable. |
| First-time provision (inside VM) | `cd ~/work/<name> && ./tools/provision` (~10–20 min) |
| Start Claude (inside VM) | `claude` first time, `claude --continue` to resume last session in cwd, `claude --resume` for picker |

## Workflow

After editing anything in `vm/`:

1. **Edit and commit** as usual on the host.
2. **Recreate the VM** with `bin/create-worktree.sh --rebuild <name>` — the
   script re-copies these files into the fresh machine. Existing VMs keep
   their old copy until you rebuild.

OrbStack auto-mounts your Mac filesystem (including `$HOME`) into the VM
at the same paths, so the in-place refresh is a one-liner from the Mac:

```sh
orb -m <name> cp /Users/$USER/terminal-dev-setup/vm/claude-settings.json ~/.claude/settings.json
```

(`$USER` expands on the Mac — by default OrbStack provisions the VM with
the same username, so the path resolves correctly on both sides.)

## Why slim

The VM is short-lived (one per Zulip branch / experiment). Heavyweight
nvim plugins (LSP, telescope, treesitter) take minutes to install on
first launch — a cost you'd pay every time you spin up a new worktree.
The slim `nvim/init.lua` uses `:Ggrep` (fugitive) for code navigation;
that's enough for quick edits inside the VM. Note that `init.lua` is
**not auto-deployed** by `bin/create-worktree.sh` — only
`claude-settings.json` is. If you want the slim nvim too, copy it in:

```sh
orb -m <name> mkdir -p ~/.config/nvim
orb -m <name> cp /Users/$USER/terminal-dev-setup/vm/nvim/init.lua ~/.config/nvim/init.lua
```

Claude runs in plan mode by default in the VM so multi-step changes
get an explicit approval gate before they touch the dev tree. No
`hooks` are configured: `notify-send` needs a desktop session the
headless VM doesn't have, and the in-terminal pause is signal enough
when you're SSHed in.
