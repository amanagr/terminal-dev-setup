# vm/ — Ubuntu-in-Docker dev container

Files here are shipped into each Vagrant-managed Docker container that
`bin/create-worktree.sh` provisions. The container runs Zulip's dev server
and Claude. Actual code editing happens in **VSCode on the host** (with
the Claude CLI in VSCode's integrated terminal); inside the container the
only editor is the default `vim` — used for git commit messages, quick
fixes over `vagrant ssh`, etc.

We use Zulip's documented recommended setup on macOS (`vagrant up
--provider=docker`) verbatim — bugs reproduce on the upstream-supported
config and are easy to file upstream.

## Contents

| File | Deployed inside the container at |
| ---- | ------------------------------- |
| `bash-aliases.sh`      | `~/.config/terminal-dev-setup/aliases.sh` |
| *(no `claude-settings.json` here)* | claude settings are shared with the host — `bin/create-worktree.sh` ships [`../host/claude-settings.json`](../host/claude-settings.json) with the `hooks` block stripped (host hooks reference tmux/notification scripts that don't exist headless) into `~/.claude/settings.json` |

The bash aliases are sourced from `~/.bashrc` (between `# >>> managed-by:
create-worktree.sh >>>` / `<<<` markers that the script rewrites on every
run). Same for `~/.zulip-dev-env.sh`, which exports:

| Var | Value |
| --- | ----- |
| `EXTERNAL_HOST`   | `localhost:<port>` (per-worktree port assigned by `create-worktree.sh`) |
| `WORKTREE_DIR`    | host path to the worktree (e.g. `/Users/$USER/work/<name>`) |

`WORKTREE_DIR` is the Mac-side path. Zulip's Vagrantfile bind-mounts the
worktree directory at the same path inside the container, so it resolves
directly. The container-native `$HOME` is `/home/vagrant` — a *different*
directory that does **not** contain the worktree. Don't use `~/work/<name>`;
either `zcd` (alias) or `cd "$WORKTREE_DIR"`.

## Using a worktree's container

| What | How |
| ---- | --- |
| Attach (shell as `vagrant`)     | `cd ~/work/<name> && vagrant ssh` |
| Detach                          | `exit` or `Ctrl-D` |
| Halt                            | `cd ~/work/<name> && vagrant halt` |
| Re-up after halt                | `bin/create-worktree.sh <name>` (re-pins HOST_PORT) — **don't** `vagrant up` directly |
| Hard reset                      | `bin/create-worktree.sh --rebuild <name>` (`vagrant destroy -f` + re-up + re-provision) |
| Jump to worktree (inside)       | `zcd` (alias → `cd $WORKTREE_DIR`) |
| Run dev server (inside)         | `zcd && run` (alias → `./tools/run-dev --interface=`). Serves http://localhost:&lt;port&gt;. The empty `--interface` is required — without it, run-dev binds 127.0.0.1 inside the container and Vagrant's host port forward can't reach it. |
| First-time provision            | Automatic — Zulip's Vagrantfile runs `tools/setup/vagrant-provision` (which calls `./tools/provision`) during `vagrant up`. ~10–20 min. |
| Start Claude (inside)           | `claude` first time, `claude --continue` to resume last session in cwd, `claude --resume` for picker |
| Quick edit (inside)             | `v <file>` (alias → `vim`) |

## Per-worktree port

Each worktree gets a sequential `HOST_PORT` (stride 10 — Zulip's Vagrantfile
forwards `host_port`, `host_port+3`, `host_port+4`). The mapping lives in
`~/.config/terminal-dev-setup/worktree-ports.tsv`. The first worktree the
script runs against gets 9991; subsequent worktrees get 10001, 10011, …
(order of first run, not name — edit the tsv by hand to reassign, but a
reassigned port only takes effect after `--rebuild`, which destroys the
container's writable layer and re-runs Zulip's full provision).

The script rewrites a managed block in `~/.zulip-vagrant-config` before
each `vagrant up`, since that file is `$HOME`-global. Each running
container's port mapping is pinned at `docker run` time, so parallel
worktrees coexist.

**Important**: never `vagrant up` or `vagrant reload` outside of
`create-worktree.sh` — the global config may currently hold a different
worktree's port.

## Tools installed by the provision step

`create-worktree.sh` installs these on top of Zulip's own provision
(all idempotent on re-run):

- **claude** — Anthropic CLI, via `curl … | bash` from `claude.ai/install.sh`.
- **gh** — GitHub CLI, via the official apt repo at `cli.github.com/packages`
  (keyring under `/etc/apt/keyrings/` per current Debian guidance — `apt-key`
  is deprecated since Ubuntu 22.04). Authenticate with `gh auth login` on
  first use.
- **git config** — `core.editor = vim` set globally so commit messages,
  rebases, etc. open in vim instead of nano.

`git`, `curl`, `jq`, and `vim` come from Zulip's own provision (vagrant-provision
→ ./tools/provision) and the base image (`tools/setup/dev-vagrant-docker/Dockerfile`),
so no extra install step here.

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
(the container's settings come from the host file now):

1. **Edit and commit** as usual on the host.
2. **Re-run `bin/create-worktree.sh <name>`** for each existing container
   (no `--rebuild` needed — the script re-uploads aliases/settings and
   rewrites the managed `~/.bashrc` block on every run). For a hard reset,
   use `bin/create-worktree.sh --rebuild <name>`.

Ad-hoc refresh of one already-running container is a one-liner:

```sh
cd ~/work/<name> && vagrant upload \
    /Users/$USER/terminal-dev-setup/vm/bash-aliases.sh \
    /home/vagrant/.config/terminal-dev-setup/aliases.sh
```

For `host/claude-settings.json`, pipe through jq into a tempfile first
(vagrant upload takes a file source, not stdin):

```sh
tmp=$(mktemp) && \
    jq 'del(.hooks)' /Users/$USER/terminal-dev-setup/host/claude-settings.json > "$tmp" && \
    ( cd ~/work/<name> && vagrant upload "$tmp" /home/vagrant/.claude/settings.json ) && \
    rm "$tmp"
```

`hooks` is stripped because the host's notification + tmux-state hooks
point at scripts under `~/.local/bin/` that don't exist in the container
and don't make sense headless (`notify-send` needs a desktop session, and
the in-terminal pause is signal enough when you're SSHed in). Everything
else — model, permissions, `effortLevel`, plugins — comes through as-is.
