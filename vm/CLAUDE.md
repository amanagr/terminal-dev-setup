# vm/ — Ubuntu-in-OrbStack dev VM

Files in this directory are shipped into each OrbStack Linux machine that
`bin/create-worktree.sh` provisions. The VM runs Zulip's dev server, Claude,
**and the full-featured Neovim** (LSP via Mason, telescope, treesitter,
blink.cmp). This is the primary editing environment — the host's nvim is
deliberately slim.

## Contents

| File | Deployed inside the VM at |
| ---- | ------------------------- |
| `claude-settings.json` | `~/.claude/settings.json` |
| `nvim/init.lua`        | `~/.config/nvim/init.lua` |
| `nvim/picker-ignore`   | `~/.config/fd/ignore` |
| `bash-aliases.sh`      | `~/.config/terminal-dev-setup/aliases.sh` |

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
| Edit a file (inside VM) | `v <file>` (alias → `nvim`) |

## Tools installed by the provision step

`create-worktree.sh` installs these into the VM (all idempotent on re-run):

- **claude** — Anthropic CLI, via `curl … | bash` from `claude.ai/install.sh`.
- **gh** — GitHub CLI, via the official apt repo at `cli.github.com/packages`
  (keyring under `/etc/apt/keyrings/` per current Debian guidance — `apt-key`
  is deprecated since Ubuntu 22.04). Authenticate with `gh auth login` on
  first use.
- **nvim** — official Linux x86_64 tarball (`nvim-linux-x86_64.tar.gz` from
  upstream `releases/latest`), extracted to `/opt/nvim-linux-x86_64/`. The
  aliases file prepends `/opt/nvim-linux-x86_64/bin` to `PATH`.
- **nvim deps (apt)** — `build-essential` (treesitter parsers,
  telescope-fzf-native), `ripgrep` (telescope live_grep + multigrep),
  `fd-find` (telescope find_files; Ubuntu names the binary `fdfind`, so
  the script also symlinks `~/.local/bin/fd → fdfind`), `sqlite3` +
  `libsqlite3-dev` (smart-open.nvim via sqlite.lua), `unzip` (some
  Mason language servers).
- **ruff** — Astral's standalone installer (`astral.sh/ruff/install.sh`)
  drops the binary at `~/.local/bin/ruff`. The init.lua's Mason setup
  intentionally skips ruff because Mason's pip route needs pip/pipx
  available; `vim.lsp.enable` picks the on-PATH binary up at runtime.

Why the tarball and not `apt install neovim`: Ubuntu 24.04 (noble) ships
0.9.5, behind plugin requirements (e.g. blink.cmp, snacks). The upstream
build is the same one the host installs.

### First-run sequence

The OS-level deps above let nvim launch and most plugins work. **Mason's
LSP servers (pyright, ts_ls, eslint, lua_ls, bashls, marksman) require
node** — which comes from Zulip's `./tools/provision`, not this script.
Order matters:

1. `bin/create-worktree.sh <name>` (from the host) — installs nvim + deps.
2. Inside the VM: `zcd && ./tools/provision` — Zulip provisions node,
   python venv, postgres, etc.
3. Inside the VM: `nvim` — first launch auto-installs lazy.nvim and the
   plugin set, then `:MasonInstall`s the language servers in the
   background. Treesitter parsers compile lazily as you open files in
   each language.

If you launch nvim before step 2, the editor itself works fine, but
Mason will error on the node-based servers. Re-launch (or
`:MasonInstall`) after provision completes.

Clipboard goes through nvim 0.10+'s built-in OSC52 provider, so yanks
into `+` reach the Mac clipboard through the terminal (Ghostty supports
OSC52) even though the VM has no xclip/wl-clipboard.

## Aliases (highlights)

Full list in [`bash-aliases.sh`](./bash-aliases.sh). The non-obvious ones:

| Alias / fn | Does |
| ---------- | ---- |
| `zcd`      | `cd $WORKTREE_DIR` |
| `run`      | `./tools/run-dev --interface=` (the empty-interface form) |
| `zlint`    | `cd $WORKTREE_DIR && ./tools/lint --modified` |
| `g`, `gs`, `gd`, `gl`, `gla`, `gco`, `gcb`, … | usual git shortcuts (mirrors host) |
| `gshow`, `glf`, `gls`, `ggrep`, `gfix`, `gdiverg` | git helper functions |
| `v` / `vi` / `vim` | `nvim` |
| `ll`, `..`, `...` | better `ls` / parent-dir `cd` |

## Workflow

After editing anything in `vm/`:

1. **Edit and commit** as usual on the host.
2. **Re-run `bin/create-worktree.sh <name>`** for each existing VM (no
   `--rebuild` needed — the provision step is idempotent and re-copies
   `claude-settings.json`, `init.lua`, `picker-ignore`, `bash-aliases.sh`,
   and rewrites the managed `~/.bashrc` block). For a hard reset, use
   `bin/create-worktree.sh --rebuild <name>`.

OrbStack auto-mounts your Mac filesystem (including `$HOME`) into the VM
at the same paths, so an ad-hoc refresh is also a one-liner:

```sh
orb -m <name> cp /Users/$USER/terminal-dev-setup/vm/claude-settings.json ~/.claude/settings.json
```

(`$USER` expands on the Mac — by default OrbStack provisions the VM with
the same username, so the path resolves correctly on both sides.)

## Why the heavy nvim lives here (not on the host)

The host is a launchpad: tmux, ghostty, browsers, attach to VMs. Actual
code reading/editing happens inside the VM where the source tree, venv,
node_modules, and language servers all match each other and Zulip's
runtime. Putting the full LSP + telescope + treesitter stack VM-side
means the language servers see the same Python interpreter and
node_modules Zulip actually runs against — no cross-machine path
mismatches, no host needing to know about per-worktree Python venvs.

The host's `nvim/init.lua` is intentionally slim (git-grep + oil +
fugitive + gitsigns + which-key) — enough for quick edits to dotfiles
on the Mac itself.

Claude runs in plan mode by default in the VM so multi-step changes
get an explicit approval gate before they touch the dev tree. No
`hooks` are configured: `notify-send` needs a desktop session the
headless VM doesn't have, and the in-terminal pause is signal enough
when you're SSHed in.
