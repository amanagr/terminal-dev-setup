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
| `claude-bell.sh`       | `~/.local/bin/claude-bell.sh` *(chmod +x in-container)* |
| `claude-hooks.json`    | merged in as the `.hooks` block of `~/.claude/settings.json` (not a standalone file in the container) |
| *(no `claude-settings.json` here)* | claude settings are shared with the host — `bin/create-worktree.sh` ships [`../host/claude-settings.json`](../host/claude-settings.json) with its `hooks` block **replaced** by [`claude-hooks.json`](./claude-hooks.json) (the host's tmux/desktop hooks can't run headless; the VM block is a terminal-bell alert via `claude-bell.sh`) into `~/.claude/settings.json` |

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
| Run dev server (inside)         | `zcd && run` (alias → `./tools/run-dev --interface=`). Serves http://localhost:&lt;port&gt;. The empty `--interface` is defensive — `run-dev` already defaults to bind-all when the OS user is `vagrant` (see run-dev:92-104), but the explicit form is robust against upstream changes. |
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

### Webpack HMR on non-9991 worktrees

Zulip's `tools/run-dev` always passes `--port=9994` to `tools/webpack`, and
webpack-dev-server's HMR client connects directly to `ws://localhost:9994/ws`,
bypassing the proxy. With `HOST_PORT != 9991`, the Vagrant forward for 9994
lands at host port `host_port+3` instead of 9994 — so HMR breaks on those
worktrees (static UI loads through the proxy, but hot reload + anything
fetched via the webpack-dev-server websocket dies).

A small upstream-friendly patch is committed locally on Zulip branch
`fix-webpack-client-port-for-non-default-host-port` (in `~/work/zulip`):
`tools/webpack` gains a `--hmr-client-port` option mapped to webpack-dev-server's
`--client-web-socket-url-port`; `tools/run-dev` derives its value from
`EXTERNAL_HOST` (which already carries the host-side proxy port) plus the
constant offset between proxy and webpack ports, so no new env-var contract
is introduced. With `EXTERNAL_HOST=localhost:10001`, run-dev computes 10004
and passes `--hmr-client-port=10004` automatically.

To use the fix on a non-`main` worktree, merge or cherry-pick the patch
into that worktree's branch. The patch is the kind of thing worth filing
upstream — see the commit message for the rationale.

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

`curl` is in the base image (`tools/setup/dev-vagrant-docker/Dockerfile`);
`git`, `jq`, and `vim` come from Zulip's own provision (vagrant-provision
→ `./tools/provision`). So no extra install step here.

## Aliases (highlights)

Full list in [`bash-aliases.sh`](./bash-aliases.sh). The non-obvious ones:

| Alias / fn | Does |
| ---------- | ---- |
| `zcd`      | `cd $WORKTREE_DIR` |
| `run`      | `./tools/run-dev --interface=` (the empty-interface form) |
| `zlint`    | `cd $WORKTREE_DIR && ./tools/lint --modified` |
| `live-update` | cherry-picks `fix-webpack-client-port-for-non-default-host-port` onto the current branch — guarded: no-ops if the patch is already in HEAD's history, errors actionably on missing-ref or conflict, never leaves a sticky CHERRY_PICK_HEAD. See §"Webpack HMR on non-9991 worktrees" |
| `g`, `gs`, `gd`, `gl`, `gla`, `gco`, `gcb`, … | usual git shortcuts (mirrors host) |
| `gshow`, `glf`, `gls`, `ggrep`, `gfix`, `gdiverg` | git helper functions |
| `v` / `vi` | `vim` |
| `ll`, `..`, `...` | better `ls` / parent-dir `cd` |

## Workflow

After editing `vm/bash-aliases.sh` *or* `host/claude-settings.json`
(the container's settings come from the host file now), sync the change
into every running container — don't just commit. The fast path is a
one-liner `vagrant upload`; full `create-worktree.sh` re-run is the
"hard reset" alternative.

**Primary flow** — push directly into each running container:

For `vm/bash-aliases.sh`:

```sh
cd ~/work/<name> && vagrant upload \
    /Users/$USER/terminal-dev-setup/vm/bash-aliases.sh \
    /home/vagrant/.config/terminal-dev-setup/aliases.sh
```

For `host/claude-settings.json` (or `vm/claude-hooks.json`), inject the VM
hooks via jq into a tempfile first (vagrant upload takes a file source, not
stdin), and re-upload the bell script if it changed:

```sh
R=/Users/$USER/terminal-dev-setup
tmp=$(mktemp) && \
    jq --slurpfile vmhooks "$R/vm/claude-hooks.json" '.hooks = $vmhooks[0]' \
       "$R/host/claude-settings.json" > "$tmp" && \
    ( cd ~/work/<name> && \
      vagrant upload "$tmp" /home/vagrant/.claude/settings.json && \
      vagrant upload "$R/vm/claude-bell.sh" /home/vagrant/.local/bin/claude-bell.sh && \
      vagrant ssh --no-tty -c "chmod +x ~/.local/bin/claude-bell.sh" ) && \
    rm "$tmp"
```

Then commit on the host as usual.

**Hard reset variant** (slower, also rewrites `~/.bashrc` block + re-runs
all post-up provisioning): `bin/create-worktree.sh <name>` (no `--rebuild` —
the script is idempotent). Use this if the bashrc managed block has drifted
or you want all post-up steps refreshed in one go.

The host's `hooks` are **replaced** (not just stripped) because they point at
host-only scripts under `~/.local/bin/`: the tmux-state machine drives the
*host's* status-bar glyph (the container can't reach the host tmux), and the
desktop toasts need a desktop session the container doesn't have. The VM block
(`claude-hooks.json` → `claude-bell.sh`) keeps the *intent* of the two "Claude
is blocked on you" toasts — permission prompts and AskUserQuestion options — as
a terminal **bell** (`\a`), which rides the `vagrant ssh` / VSCode pty back to
your host terminal. Everything else — model, permissions, `effortLevel`,
plugins — comes through as-is.

The tmux "working" tab animation and any status-bar glyphs do **not** work for
the container's Claude, for the same reason the toasts don't: they're set by
`claude-tmux-state.sh` on the *host's* tmux panes, and Claude running inside
the container can't reach the host tmux server. The bell is the only
cross-environment signal.
