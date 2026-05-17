# vm/ — Ubuntu-in-OrbStack dev VM

Files in this directory are shipped into each OrbStack Linux machine that
`bin/create-worktree.sh` provisions. The VM runs Zulip's dev server + Claude;
both a slim Neovim and a small bash-alias set are installed for quick
in-VM edits and git work. Heavy editing still belongs on the host.

## Contents

| File | Deployed inside the VM at |
| ---- | ------------------------- |
| `claude-settings.json` | `~/.claude/settings.json` |
| `nvim/init.lua`        | `~/.config/nvim/init.lua` |
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

`create-worktree.sh` installs these into the VM (idempotent on re-run):

- **claude** — Anthropic CLI, via `curl … | bash` from `claude.ai/install.sh`.
- **gh** — GitHub CLI, via the official apt repo at `cli.github.com/packages`
  (keyring under `/etc/apt/keyrings/` per current Debian guidance — `apt-key`
  is deprecated since Ubuntu 22.04). Authenticate with `gh auth login` on
  first use.
- **nvim** — official Linux x86_64 tarball (`nvim-linux-x86_64.tar.gz` from
  upstream `releases/latest`), extracted to `/opt/nvim-linux-x86_64/`. The
  aliases file prepends `/opt/nvim-linux-x86_64/bin` to `PATH`.

Why the tarball and not `apt install neovim`: Ubuntu 24.04 (noble) ships
0.9.5, behind the 0.9.4+ floor of `which-key.nvim` and adrift from the
host (which uses ≥ 0.12 from the same upstream). One source of nvim ⇒
the same `init.lua` boots cleanly on both.

First nvim launch auto-installs lazy.nvim and the plugin set in
`init.lua` (github-theme, oil, gitsigns, fugitive, lualine, nvim-surround,
nvim-autopairs, which-key). Takes ~15 seconds — no LSP / treesitter /
telescope, so no compile step. Clipboard goes through nvim 0.10+'s
built-in OSC52 provider, so yanks into `+` reach the Mac clipboard
through the terminal (Ghostty supports OSC52) even though the VM has no
xclip/wl-clipboard.

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
   `claude-settings.json`, `init.lua`, `bash-aliases.sh`, and rewrites
   the managed `~/.bashrc` block). For a hard reset, use
   `bin/create-worktree.sh --rebuild <name>`.

OrbStack auto-mounts your Mac filesystem (including `$HOME`) into the VM
at the same paths, so an ad-hoc refresh is also a one-liner:

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
that's enough for quick edits inside the VM.

Claude runs in plan mode by default in the VM so multi-step changes
get an explicit approval gate before they touch the dev tree. No
`hooks` are configured: `notify-send` needs a desktop session the
headless VM doesn't have, and the in-terminal pause is signal enough
when you're SSHed in.
