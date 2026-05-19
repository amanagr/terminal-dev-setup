# vm/ — Ubuntu-in-OrbStack dev VM

Files in this directory are shipped into each OrbStack Linux machine that
`bin/create-worktree.sh` provisions. The VM runs Zulip's dev server and
Claude. Actual code editing happens in **VSCode on the host** (with the
Claude CLI in VSCode's integrated terminal); inside the VM, the only
editor is the default `vim` — used for git commit messages, quick fixes
over `orb -m <name>`, etc.

## Contents

| File | Deployed inside the VM at |
| ---- | ------------------------- |
| `bash-aliases.sh`      | `~/.config/terminal-dev-setup/aliases.sh` |
| *(no `claude-settings.json` here)* | claude settings are shared with the host — `bin/create-worktree.sh` ships [`../host/claude-settings.json`](../host/claude-settings.json) with the `hooks` block stripped (host hooks reference tmux/notification scripts that don't exist on the VM) into `~/.claude/settings.json` |

The bash aliases are sourced from `~/.bashrc` (between `# >>> managed-by:
create-worktree.sh >>>` / `<<<` markers that the script rewrites on every
run). Same for `~/.zulip-dev-env.sh`, which exports:

| Var | Value |
| --- | ----- |
| `EXTERNAL_HOST`   | `<name>.orb.local:9991` |
| `WORKTREE_DIR`    | host path to the worktree (e.g. `/Users/$USER/work/<name>`) |

`WORKTREE_DIR` is the Mac-side path. OrbStack mounts the Mac home into the
VM at the same path (`/Users/<you>/…`), so it resolves directly inside the
machine. The VM-native `$HOME` is `/home/<you>` — a *different* directory
that does **not** contain the worktree. Don't use `~/work/<name>`; either
`zcd` (alias) or `cd "$WORKTREE_DIR"`.

## Using the VM

| What | How |
| ---- | --- |
| Attach (shell as your Mac user) | `orb -m <name>` |
| Detach | `exit` or `Ctrl-D` |
| Jump to worktree (inside VM)    | `zcd` (alias → `cd $WORKTREE_DIR`) |
| Run dev server (inside VM) | `zcd && run` (alias → `./tools/run-dev --interface=`). Serves http://&lt;name&gt;.orb.local:9991. The empty `--interface` is required — without it, run-dev binds only to 127.0.0.1 inside the VM and the `<name>.orb.local` address (a separate VM interface) is unreachable. |
| First-time provision (inside VM) | `zcd && ./tools/provision` (~10–20 min) |
| Start Claude (inside VM) | `claude` first time, `claude --continue` to resume last session in cwd, `claude --resume` for picker |
| Quick edit (inside VM) | `v <file>` (alias → `vim`) |

## Tools installed by the provision step

`create-worktree.sh` installs these into the VM (all idempotent on re-run):

- **claude** — Anthropic CLI, via `curl … | bash` from `claude.ai/install.sh`.
- **gh** — GitHub CLI, via the official apt repo at `cli.github.com/packages`
  (keyring under `/etc/apt/keyrings/` per current Debian guidance — `apt-key`
  is deprecated since Ubuntu 22.04). Authenticate with `gh auth login` on
  first use.
- **git config** — `core.editor = vim` set globally so commit messages,
  rebases, etc. open in vim instead of nano.

`vim` itself is the default Ubuntu `vim-tiny` / `vim` package already on
the base image; no install step needed.

## Aliases (highlights)

Full list in [`bash-aliases.sh`](./bash-aliases.sh). The non-obvious ones:

| Alias / fn | Does |
| ---------- | ---- |
| `zcd`      | `cd $WORKTREE_DIR` |
| `run`      | `./tools/run-dev --interface=` (the empty-interface form) |
| `zlint`    | `cd $WORKTREE_DIR && ./tools/lint --modified` |
| `g`, `gs`, `gd`, `gl`, `gla`, `gco`, `gcb`, … | usual git shortcuts (mirrors host) |
| `gshow`, `glf`, `gls`, `ggrep`, `gfix`, `gdiverg` | git helper functions |
| `v` / `vi` | `vim` |
| `ll`, `..`, `...` | better `ls` / parent-dir `cd` |

## Workflow

After editing `vm/bash-aliases.sh` *or* `host/claude-settings.json`
(the VM's settings come from the host file now):

1. **Edit and commit** as usual on the host.
2. **Re-run `bin/create-worktree.sh <name>`** for each existing VM (no
   `--rebuild` needed — the provision step is idempotent and re-copies
   the settings/aliases and rewrites the managed `~/.bashrc` block).
   For a hard reset, use `bin/create-worktree.sh --rebuild <name>`.

OrbStack auto-mounts your Mac filesystem (including `$HOME`) into the VM
at the same paths, so an ad-hoc refresh of a running VM is also a
one-liner — strip `hooks` with `jq` and write directly:

```sh
jq 'del(.hooks)' /Users/$USER/terminal-dev-setup/host/claude-settings.json \
    | orb -m <name> tee ~/.claude/settings.json >/dev/null
```

(`$USER` expands on the Mac — by default OrbStack provisions the VM with
the same username, so the path resolves correctly on both sides.)

`hooks` is stripped because the host's notification + tmux-state hooks
point at scripts under `~/.local/bin/` that don't exist on the VM and
don't make sense headless (`notify-send` needs a desktop session, and
the in-terminal pause is signal enough when you're SSHed in). Everything
else — model, permissions, `effortLevel`, plugins — comes through as-is.
