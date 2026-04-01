# terminal-dev-setup

Zulip development environment for Ubuntu. Neovim 0.12+, tmux, lazygit,
and shell tooling configured for the Zulip stack (Python/Django +
TypeScript + Handlebars).

## Install

```bash
git clone <this-repo> ~/terminal-dev-setup
cd ~/terminal-dev-setup
./install.sh
```

Re-running is safe — existing files are backed up to
`~/.dotfiles-backup/<timestamp>/`.

After install: open tmux and press `prefix + I` to install tmux
plugins, then open nvim and let lazy.nvim auto-install on first launch.

## Zulip repository setup

After running `install.sh`, set up the Zulip repo:

```bash
# Set your git identity
git config --global user.name "Aman Agrawal"
git config --global user.email "amanagr@zulip.com"

# Clone the repo
git clone git@github.com:amanagr/zulip.git ~/zulip
cd ~/zulip

# Add the upstream remote with full branch names
git remote add upstream https://github.com/zulip/zulip.git
git remote set-url --push upstream nobody  # prevent accidental pushes to upstream
git fetch upstream

# Provision the dev environment (installs dependencies, sets up database, etc.)
./tools/provision
```

### Git config notes

`install.sh` configures these globally:

- **`core.editor`** = `nvim`
- **`core.pager`** = `delta` (side-by-side diffs with line numbers)
- **`diff.tool`** = `nvimdiff` (open diffs in nvim split view)
- **`diff.colorMoved`** = `default` (highlights moved code blocks in diffs)
- **`core.excludesFile`** = `~/.gitignore` (global gitignore)

### Typical Zulip workflow

```bash
# Start your dev session
dev                          # attach/create tmux 'dev' session
zcd                          # cd ~/zulip
run                          # start the dev server

# In another tmux pane: work on a feature
git fetch upstream
gcb my-feature upstream/main # create branch from latest upstream

# ... edit code in nvim ...
zlint                        # lint modified files
./tools/test-backend zerver.tests.test_relevant_module

# Review and commit
lg                           # open lazygit to stage/commit/rebase
```

## Architecture notes

- **Leader key** is `Space` in Neovim.
- **tmux prefix** is `Ctrl-b` (default).
- Pane navigation (`Ctrl-h/j/k/l`) is shared seamlessly between tmux
  and Neovim via vim-tmux-navigator.
- `.hbs` files are mapped to `handlebars` filetype and use
  vim-mustache-handlebars (not treesitter glimmer — it doesn't work
  for Zulip's Handlebars syntax).
- LSP uses Neovim 0.12 native `vim.lsp.config`/`vim.lsp.enable`, not
  nvim-lspconfig. Mason handles installation only.
- Treesitter uses the 0.12 API: `require("nvim-treesitter").install()`
  for parsers, `vim.treesitter.start()` via FileType autocmd for
  highlighting.
- Completion is blink.cmp (Rust fuzzy matching, built-in LSP/path/
  snippet/buffer sources).

## Keyboard shortcuts

### Neovim — Navigation

| Key | Mode | Action |
|-----|------|--------|
| `Ctrl-p` | normal | Find files (Telescope) |
| `Space ff` | normal | Find files |
| `Space fg` | normal | Live grep across project |
| `Space fb` | normal | Switch buffer |
| `Space fo` | normal | Recent files |
| `Space fr` | normal | Resume last Telescope search |
| `Space fs` | normal | Grep word under cursor |
| `Space fh` | normal | Search help tags |
| `Space e` | normal | Open file explorer (oil.nvim) |
| `-` | normal | Open parent directory (oil.nvim) |
| `Ctrl-h/j/k/l` | normal | Move between splits (also works across tmux panes) |
| `Ctrl-d` / `Ctrl-u` | normal | Half-page down/up (cursor stays centered) |

### Neovim — LSP

| Key | Mode | Action |
|-----|------|--------|
| `gd` | normal | Go to definition |
| `gr` | normal | Find references |
| `gI` | normal | Go to implementation |
| `gD` | normal | Go to declaration |
| `K` | normal | Hover documentation |
| `Space rn` | normal | Rename symbol |
| `Space ca` | normal | Code action |
| `Space D` | normal | Type definition |
| `]d` / `[d` | normal | Next/prev diagnostic |
| `]]` / `[[` | normal | Next/prev LSP reference (snacks.words) |

### Neovim — Completion (blink.cmp)

| Key | Mode | Action |
|-----|------|--------|
| `Ctrl-Space` | insert | Show/toggle completion + docs |
| `Ctrl-n` / `Ctrl-p` | insert | Next/prev completion item |
| `Ctrl-y` | insert | Accept completion |
| `Ctrl-e` | insert | Dismiss completion |
| `Tab` / `Shift-Tab` | insert | Jump forward/back in snippet |
| `Ctrl-b` / `Ctrl-f` | insert | Scroll documentation |
| `Ctrl-k` | insert | Signature help |

### Neovim — Git

| Key | Mode | Action |
|-----|------|--------|
| `Space gg` | normal | Git status (fugitive) |
| `Space gd` | normal | Vertical diff split |
| `Space gl` | normal | Git log (last 30 commits) |
| `Space gL` | normal | Git log graph (all branches) |
| `Space gc` | normal | Browse commits (Telescope) |
| `Space gb` | normal | Browse branches (Telescope) |
| `Space gs` | normal | Git status (Telescope) |
| `]h` / `[h` | normal | Next/prev git hunk |
| `Space hs` | normal | Stage hunk |
| `Space hr` | normal | Reset hunk |
| `Space hp` | normal | Preview hunk inline |
| `Space hb` | normal | Blame line (full commit) |
| `Space hd` | normal | Diff against index |
| `Space hD` | normal | Diff against last commit |
| `Enter` | normal (git log buffer) | Open commit under cursor in difftool |

### Neovim — Diagnostics (trouble.nvim)

| Key | Mode | Action |
|-----|------|--------|
| `Space xx` | normal | Toggle diagnostics panel (all files) |
| `Space xd` | normal | Toggle diagnostics panel (current buffer) |
| `Space xq` | normal | Toggle quickfix list |
| `Space xl` | normal | Toggle location list |

### Neovim — Editing

| Key | Mode | Action |
|-----|------|--------|
| `gcc` | normal | Toggle comment (built-in, ts-comments aware) |
| `gc` | visual | Toggle comment on selection |
| `ys{motion}{char}` | normal | Add surround (e.g., `ysiw"` to surround word with quotes) |
| `cs{old}{new}` | normal | Change surround (e.g., `cs"'` to change `"` to `'`) |
| `ds{char}` | normal | Delete surround |
| `J` / `K` | visual | Move selected lines down/up |
| `Space w` | normal | Save file |
| `]b` / `[b` | normal | Next/prev buffer |
| `Space bd` | normal | Delete buffer |
| `]q` / `[q` | normal | Next/prev quickfix item |

### Neovim — Discovery

Press `Space` and wait 500ms to see all available leader keybindings
via which-key. Groups: `f` (Find), `g` (Git), `h` (Hunks),
`b` (Buffer), `x` (Diagnostics).

### tmux

| Key | Action |
|-----|--------|
| `prefix \|` | Split pane horizontally |
| `prefix -` | Split pane vertically |
| `prefix h/j/k/l` | Select pane (vim-style) |
| `Ctrl-h/j/k/l` | Smart pane switch (works in both tmux and nvim) |
| `prefix H/J/K/L` | Resize pane (repeatable) |
| `prefix Enter` | Enter copy mode (vi keys, `v` to select, `y` to copy) |
| `prefix r` | Reload tmux config |
| `prefix s` | Session picker |
| `prefix S` | Create new named session |
| `prefix c` | New window (inherits current path) |
| `prefix I` | Install TPM plugins (first run) |

### Shell aliases

| Alias | Command |
|-------|---------|
| `dev` | Attach to tmux `dev` session or create it |
| `v` / `vi` / `vim` | nvim |
| `lg` | lazygit |
| `gs` | `git status -sb` |
| `gd` / `gds` | `git diff` / `git diff --staged` |
| `gl` / `gla` | `git log --oneline` / with graph |
| `gco` / `gcb` | `git checkout` / `git checkout -b` |
| `gcp` | `git cherry-pick` |
| `grb` / `grbi` | `git rebase` / `git rebase -i` |
| `gst` / `gstp` | `git stash` / `git stash pop` |
| `gshow [ref]` | Show commit diff with delta |
| `glf [n]` | Git log with file stats (last n, default 10) |
| `gls <pattern>` | Search git log messages |
| `ggrep <string> [path]` | Search code across git history (`-S`) |
| `zcd` | `cd ~/zulip` |
| `zlint` | Run Zulip linters on modified files |
| `run` | `./tools/run-dev interface=""` |

### Shell — fzf functions

| Command | Action |
|---------|--------|
| `Ctrl-T` | Fuzzy find files (insert path) |
| `Ctrl-R` | Fuzzy search shell history |
| `fe` | Fuzzy find file and open in nvim (with bat preview) |
| `fcd` | Fuzzy find directory and cd into it |
| `frg [pattern]` | Ripgrep + fzf, open result in nvim at the matching line |

## Installed tools

Installed via `install.sh`:

| Tool | Purpose |
|------|---------|
| neovim 0.12+ | Editor (appimage) |
| tmux | Terminal multiplexer |
| lazygit | TUI git client |
| ripgrep (rg) | Fast code search |
| fzf | Fuzzy finder |
| fd-find (fd) | Fast file finder |
| bat | Cat with syntax highlighting |
| git-delta | Git diff viewer (side-by-side, line numbers) |
| tig | TUI git log browser |
| tree-sitter-cli | Parser compiler (required by nvim-treesitter) |
| jq | JSON processor |

## Neovim plugins

| Plugin | Purpose |
|--------|---------|
| lazy.nvim | Plugin manager |
| catppuccin | Color theme (mocha, transparent bg) |
| telescope.nvim | Fuzzy finder UI |
| oil.nvim | File explorer (edit filesystem like a buffer) |
| gitsigns.nvim | Inline git blame, hunk staging |
| vim-fugitive | Git commands inside nvim |
| nvim-treesitter | Syntax highlighting (0.12 API) |
| nvim-treesitter-context | Sticky function/class context at top of buffer |
| mason.nvim | LSP server installer |
| blink.cmp | Completion engine (LSP, path, snippets, buffer) |
| trouble.nvim | Diagnostics panel |
| snacks.nvim | Bigfile handling + LSP word highlighting |
| vim-tmux-navigator | Seamless tmux/nvim pane switching |
| lualine.nvim | Statusline |
| nvim-surround | Surround motions (ys, cs, ds) |
| nvim-autopairs | Auto-close brackets/quotes |
| ts-comments.nvim | Treesitter-aware comment strings |
| which-key.nvim | Keybinding discovery popup |
| indent-blankline.nvim | Indent guides |
| vim-mustache-handlebars | Handlebars syntax for .hbs files |
| friendly-snippets | Snippet collection for blink.cmp |

## Gotchas

- **fzf in zsh**: Uses `fzf --zsh`, not `--bash`. The `frg` function is
  named to avoid collision with zsh's `grep` alias expansion.
- **Telescope treesitter preview**: Disabled (`treesitter = false`) to
  avoid compatibility issues with the ft_to_lang shim.
- **Lualine theme**: Set to `"auto"`, not `"catppuccin"`, to avoid
  load-order issues.
- **TPM plugins**: Must press `prefix + I` inside tmux on first run to
  install tmux-resurrect and tmux-continuum.
