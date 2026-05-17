# terminal-dev-setup

Two distinct config sets for two distinct environments. They live side by side
in this repo so they can stay in sync without juggling branches.

| Directory | Target environment | What's in it |
| --------- | ------------------ | ------------ |
| [`host/`](./host/) | **macOS** (Apple Silicon, primary) — also works on modern Linux | tmux + zsh/oh-my-zsh + starship + ghostty + heavy nvim (LSP, telescope, treesitter) + claude with tmux-integrated hooks |
| [`vm/`](./vm/)     | **Ubuntu 22.04 in OrbStack** (Linux dev VM for Zulip — matches Zulip's recommended base) | slim claude (plan mode) + slim nvim (git-grep-driven) |
| [`bin/create-worktree.sh`](./bin/create-worktree.sh) | host → VM bridge | provisions an OrbStack Linux machine per worktree, ships `vm/` into it |

Each subdirectory has its own `CLAUDE.md` with deploy paths and workflow notes.

## Workflow

After every change to a tracked file:

1. **Deploy to the live path.** This repo doesn't auto-symlink — copy with `cp`.
   The destination is documented in each subdirectory's `CLAUDE.md`.
2. **Commit.** Small, focused commits. Match the style of recent commits
   (`git log --oneline -10`).

## Bootstrapping a new machine

- **Host (macOS)**: read [`host/CLAUDE.md`](./host/CLAUDE.md) — it's a linear
  recipe: install Homebrew, run the `brew install` block, deploy the configs.
- **VM**: install [OrbStack](https://orbstack.dev) once, then
  `bin/create-worktree.sh <name>` creates a fresh Zulip clone + an OrbStack
  Linux machine named `<name>`, ships `vm/` into it, and prints the
  `./tools/provision` / `./tools/run-dev` next steps. Use `--rebuild <name>`
  to destroy and re-provision an existing machine. Each machine has its own
  `<name>.orb.local` DNS name, so any number of worktrees can run dev servers
  in parallel — no shared host-port forward to collide on.
