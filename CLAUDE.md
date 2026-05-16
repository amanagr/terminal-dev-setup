# terminal-dev-setup

Two distinct config sets for two distinct environments. They live side by side
in this repo so they can stay in sync without juggling branches.

| Directory | Target environment | What's in it |
| --------- | ------------------ | ------------ |
| [`host/`](./host/) | **PopOS** (Ubuntu 24.04 base, GNOME, Wayland) | tmux + zsh/oh-my-zsh + starship + ghostty + heavy nvim (LSP, telescope, treesitter) + claude with tmux-integrated hooks |
| [`vm/`](./vm/)     | **Ubuntu 26.04 in Docker** (Vagrant/Docker dev VMs for Zulip) | slim claude (plan mode) + slim nvim (git-grep-driven) |
| [`bin/create-worktree.sh`](./bin/create-worktree.sh) | host → VM bridge | provisions a Zulip dev VM, ships `vm/` into it |

Each subdirectory has its own `CLAUDE.md` with deploy paths and workflow notes.

## Workflow

After every change to a tracked file:

1. **Deploy to the live path.** This repo doesn't auto-symlink — copy with `cp`.
   The destination is documented in each subdirectory's `CLAUDE.md`.
2. **Commit.** Small, focused commits. Match the style of recent commits
   (`git log --oneline -10`).

## Bootstrapping a new machine

- **Host (PopOS)**: read [`host/CLAUDE.md`](./host/CLAUDE.md). No install script —
  the deploy steps are explicit and short.
- **VM**: `bin/create-worktree.sh <name>` creates a fresh Zulip clone + Vagrant
  Docker VM at `~/work/<name>`, ships `vm/` into the box, and prints how to
  attach. Each invocation picks a fresh host-port block so multiple worktrees
  coexist.
