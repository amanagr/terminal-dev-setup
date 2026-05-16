# vm/ — Ubuntu-in-Docker dev VM

Files in this directory are shipped into each Vagrant/Docker VM that
`bin/create-worktree.sh` provisions. The VM runs Zulip's dev server +
Claude; Neovim editing happens on the host.

## Contents

| File | Deployed inside the VM at |
| ---- | ------------------------- |
| `claude-settings.json` | `~/.claude/settings.json` |
| `nvim/init.lua`        | `~/.config/nvim/init.lua` *(optional — see below)* |

## Workflow

After editing anything in `vm/`:

1. **Edit and commit** as usual on the host.
2. **Recreate the VM** with `bin/create-worktree.sh <new-name>` — the script
   re-copies these files into the new VM. Existing VMs keep their old
   copy until you replace them.

If you want to refresh an existing VM in-place without recreating,
`vagrant ssh -c 'cat > ~/.claude/settings.json' < vm/claude-settings.json`
from inside the worktree directory works.

## Why slim

The VM is short-lived (one per Zulip branch / experiment). Heavyweight
nvim plugins (LSP, telescope, treesitter) take minutes to bootstrap on
first launch and need network access from inside the container — both
costs you'd pay every time you spin up a new worktree. The slim
`nvim/init.lua` uses `:Ggrep` (fugitive) for code navigation; that's
enough for quick edits inside the VM.

Claude runs in plan mode by default in the VM so multi-step changes
get an explicit approval gate before they touch the dev tree.
