# terminal-dev-setup

Two distinct config sets for two distinct environments. They live side by side
in this repo so they can stay in sync without juggling branches.

| Directory | Target environment | What's in it |
| --------- | ------------------ | ------------ |
| [`host/`](./host/) | **macOS** (Apple Silicon, primary) — also works on modern Linux | tmux + zsh/oh-my-zsh + starship + ghostty + nvim as a **diffview commit-reviewer** (treesitter syntax, vivid diff colors, gutter change-bars; launched from Zed's Git Graph) + zed (commit-review task + settings) + claude with tmux-integrated hooks |
| [`vm/`](./vm/)     | **Ubuntu 22.04 in a Vagrant-managed Docker container** (matches Zulip's recommended dev setup verbatim) | claude (plan mode) + bash aliases (no nvim — default `vim` for in-VM edits, VSCode on host for real editing) |
| [`bin/create-worktree.sh`](./bin/create-worktree.sh) | host → container bridge | per-worktree Docker container via `vagrant up --provider=docker`; uploads `vm/bash-aliases.sh`, the host's `claude-settings.json` (its `hooks` swapped for `vm/claude-hooks.json` — headless pty-based signals: a terminal-bell attention alert via `vm/claude-bell.sh` + a bind-mount state file via `vm/claude-vm-state.sh` that drives the host tmux "working" glyph), installs `claude` + `gh`, and writes a managed `~/.bashrc` block inside the container |

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
- **VM**: install Docker Desktop, Vagrant, plus `git` and `jq` for the
  script's prereq check (`brew install git jq` +
  `brew install --cask vagrant docker-desktop`). Then `bin/create-worktree.sh <name>`:
  on first invocation clones the canonical `~/work/zulip` repo, then adds a
  linked `git worktree` for the given name, brings up a Vagrant-managed
  Docker container, and runs Zulip's full `./tools/provision` automatically
  (10–20 min on first run). Use `--rebuild <name>` to `vagrant destroy -f`
  and re-provision. Each worktree gets its own host port (sequential, stored
  in `~/.config/terminal-dev-setup/worktree-ports.tsv`); the dev server is
  at `http://localhost:<port>`.
