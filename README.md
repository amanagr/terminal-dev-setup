# terminal-dev-setup

Zulip development environment for Ubuntu. Neovim 0.12+, tmux, lazygit,
and shell tooling configured for the Zulip stack (Python/Django +
TypeScript + Handlebars).

## Install

```bash
git clone git@github.com:amanagr/terminal-dev-setup.git ~/terminal-dev-setup
cd ~/terminal-dev-setup
./install.sh
```

Re-running is safe — existing files are backed up to
`~/.dotfiles-backup/<timestamp>/`.

After install:

1. Log out and back in (Guake starts at login), or run `guake &`
2. Press `Ctrl+\`` to open the dropdown terminal
3. Open tmux and press `prefix + I` to install tmux plugins
4. Open nvim — lazy.nvim auto-installs plugins on first launch

## Zulip repository setup

```bash
git config --global user.name "Aman Agrawal"
git config --global user.email "amanagr@zulip.com"

git clone git@github.com:amanagr/zulip.git ~/zulip
cd ~/zulip
git remote add upstream https://github.com/zulip/zulip.git
git remote set-url --push upstream nobody
git fetch upstream

./tools/provision
```

Machine-specific environment variables (like `EXTERNAL_HOST`) go in
`~/.zshrc.local` — this file is sourced automatically if it exists.

## How the pieces fit together

```
Guake (Ctrl+` to toggle dropdown terminal)
  └── tmux (session persistence, pane management)
        ├── Pane 1: nvim (editing)
        ├── Pane 2: ./tools/run-dev (dev server)
        └── Pane 3: shell (tests, git, lazygit)
```

**Guake** is a dropdown terminal that slides down from the top of the
screen when you press `Ctrl+\``. Press again to hide it. It starts at
login and stays in the background — no need to find a terminal window.
The install script configures it fullscreen with JetBrains Mono Nerd
Font and no transparency.

- **Ctrl-h/j/k/l** moves between tmux panes AND nvim splits seamlessly
  (vim-tmux-navigator handles the handoff).
- **Starship** provides the prompt (git branch, python/node versions,
  command duration).
- **delta** renders all git diffs with side-by-side, line numbers, and
  syntax highlighting.
- **.hbs files** use vim-mustache-handlebars (not treesitter glimmer —
  it doesn't handle Zulip's Handlebars syntax).
- **LSP** uses Neovim 0.12 native `vim.lsp.config`/`vim.lsp.enable`.
  Mason handles installation only.
- **blink.cmp** provides completion with LSP, path, snippet, and buffer
  sources.

Leader key is **Space**. Press it and wait to see all available
keybindings via which-key.

---

## Workflows

### Starting your day

```bash
dev                          # attach/create tmux 'dev' session
zcd                          # cd ~/zulip
run                          # start dev server (in a dedicated pane)
```

Split tmux panes with `prefix |` (horizontal) or `prefix -` (vertical).
`prefix c` opens a new window.

### Finding code

| What you want | How |
|---------------|-----|
| Open a file by name | `Ctrl-p` or `Space ff` in nvim |
| Grep across the project | `Space fg` (Telescope live grep) |
| Grep word under cursor | `Space fs` |
| Find and open from shell | `fe` (fzf + bat preview, opens in nvim) |
| Ripgrep from shell, jump to line | `frg pattern` |
| cd into a directory via fuzzy find | `fcd` |
| Browse files in current directory | `-` (oil.nvim, navigate like a buffer) |
| Resume last Telescope search | `Space fr` |

### Reading and navigating code

| What you want | How |
|---------------|-----|
| Go to definition | `gd` |
| Find all references | `gr` |
| Go to implementation | `gI` |
| Hover docs | `K` |
| Type definition | `Space D` |
| Next/prev diagnostic | `]d` / `[d` |
| Next/prev LSP reference under cursor | `]]` / `[[` |
| Jump between quickfix results | `]q` / `[q` |
| See all diagnostics | `Space xx` |
| See diagnostics for current file | `Space xd` |

The top of the buffer shows sticky context (function/class name) via
treesitter-context.

### Editing

| What you want | How |
|---------------|-----|
| Toggle comment | `gcc` (line) or `gc` (selection) |
| Surround with quotes | `ysiw"` (surround word), `yss"` (surround line) |
| Change surrounding | `cs"'` (change `"` to `'`) |
| Delete surrounding | `ds"` |
| Move lines up/down | `J` / `K` in visual mode |
| Rename symbol (LSP) | `Space rn` |
| Code action | `Space ca` |
| Save | `Space w` |

### Completion (blink.cmp)

Completion appears automatically as you type. Sources: LSP, file
paths, snippets, buffer words.

| Key | Action |
|-----|--------|
| `Ctrl-n` / `Ctrl-p` | Navigate completion items |
| `Ctrl-y` | Accept |
| `Ctrl-e` | Dismiss |
| `Ctrl-Space` | Toggle completion + docs |
| `Tab` / `Shift-Tab` | Jump forward/back in snippet placeholders |
| `Ctrl-k` | Signature help |

### Git — daily workflow

```bash
# Start a feature branch from latest upstream
git fetch upstream
gcb my-feature upstream/main

# ... make changes ...

# Check status, stage, diff
gs                           # git status -sb
gd                           # git diff
gds                          # git diff --staged

# Lint and test before committing
zlint                        # lint modified files
./tools/test-backend zerver.tests.test_relevant_module

# Commit
lg                           # open lazygit — stage hunks, write commit
```

### Git — shell aliases quick reference

| Alias | Expands to |
|-------|-----------|
| `gs` | `git status -sb` |
| `gd` / `gds` | `git diff` / `git diff --staged` |
| `gl` / `gla` | `git log --oneline` / with `--all --graph` |
| `gco` / `gcb` | `git checkout` / `git checkout -b` |
| `gcp` | `git cherry-pick` |
| `grb` / `grbi` | `git rebase` / `git rebase -i` |
| `gst` / `gstp` | `git stash` / `git stash pop` |
| `gshow [ref]` | Show commit with delta |
| `glf [n]` | Log with file stats (default 10) |
| `gls pattern` | Search commit messages |
| `ggrep string [path]` | Search code across git history (`-S`) |

### Git — fixup workflow (Zulip commit discipline)

When you need to fix an earlier commit without creating a new one:

```bash
# Make your fix, then:
gfix <commit-hash>           # creates --fixup commit and auto-squashes

# Or step by step:
git add -p                   # stage the fix
git fixup <commit-hash>      # create fixup commit (git alias)
grbi upstream/main           # autosquash is on by default
```

`rerere` is enabled — git remembers how you resolved conflicts and
replays the resolution automatically on future rebases.

### Git — other useful commands

| Command | What it does |
|---------|-------------|
| `git amend` | Amend last commit without editing message |
| `git uncommit` | Undo last commit, keep changes staged |
| `git dw` | Word-level diff (see exactly which words changed) |
| `git recent` | List branches sorted by last commit date |
| `gdiverg [base]` | Show commits ahead/behind a base branch (default: upstream/main) |

### Git — in Neovim

| Key | Action |
|-----|--------|
| `Space gg` | Open fugitive git status |
| `Space gd` | Vertical diff split of current file |
| `Space gl` | Git log (last 30 commits) |
| `Space gL` | Git log graph (all branches) |
| `Space gc` | Browse commits (Telescope) |
| `Space gb` | Browse/switch branches (Telescope) |
| `Space gs` | Changed files (Telescope) |
| `]h` / `[h` | Jump to next/prev git hunk |
| `Space hs` | Stage hunk under cursor |
| `Space hr` | Reset hunk |
| `Space hp` | Preview hunk inline |
| `Space hb` | Full blame for current line |
| `Space hd` | Diff file against index |
| `Space hD` | Diff file against last commit |
| `Enter` (in git log) | Open commit under cursor in difftool |

Inline git blame is always visible (gitsigns, 500ms delay).

### Lazygit

Open with `lg` from the shell.

| Key | Action |
|-----|--------|
| `Space` | Stage/unstage file |
| `a` | Stage all |
| `c` | Commit |
| `A` | Amend last commit |
| `S` | Squash (in rebase) |
| `e` | Edit commit (in rebase) |
| `d` | Drop commit (in rebase) |
| `Ctrl-t` | Open file in nvim (from diff view) |
| `\|` | Cycle between delta and difftastic pagers |
| `G` | Open GitHub PR for branch (custom command) |
| `P` | Prune branches with deleted remotes (custom command) |
| `/` | Filter (fuzzy mode) |

Lazygit auto-fetches in the background and shows divergence from
main/master in the branch list.

When launched from a Neovim terminal (`:terminal lazygit`), editing a
file opens it in the parent Neovim instance (`nvim-remote` preset).

### tmux

| Key | Action |
|-----|--------|
| `prefix \|` | Split horizontally |
| `prefix -` | Split vertically |
| `Ctrl-h/j/k/l` | Smart pane switch (works in both tmux and nvim) |
| `prefix h/j/k/l` | Select pane (vim-style, prefix required) |
| `prefix H/J/K/L` | Resize pane (repeatable) |
| `prefix c` | New window (inherits current path) |
| `prefix Enter` | Copy mode (vi keys: `v` select, `y` copy) |
| `prefix r` | Reload config |
| `prefix s` | Session picker |
| `prefix S` | Create new named session |
| `prefix I` | Install TPM plugins |

Sessions auto-save every 15 minutes (tmux-continuum) and auto-restore
on tmux start (tmux-resurrect).

### Reviewing a PR

```bash
# Fetch and check out the PR
gh pr checkout 12345

# Browse the diff in lazygit
lg

# Or in the shell
gd upstream/main             # full diff against main
glf                          # see which files changed
gshow <hash>                 # inspect a specific commit with delta

# Open specific files in nvim
fe                           # fuzzy find and open
frg "function_name"          # grep and jump to line
```

---

## What's installed

### CLI tools

| Tool | Purpose | Installed via |
|------|---------|---------------|
| guake | Dropdown terminal (Ctrl+\`) | apt |
| neovim 0.12+ | Editor | appimage |
| tmux | Terminal multiplexer | apt |
| lazygit | TUI git client | GitHub releases |
| ripgrep (rg) | Fast code search | apt |
| fzf | Fuzzy finder | apt |
| fd-find (fd) | Fast file finder | apt |
| bat | Cat with syntax highlighting | apt |
| git-delta | Side-by-side diffs with line numbers | apt |
| difftastic (difft) | Structural/AST-aware diffs | GitHub releases |
| tig | TUI git log browser | apt |
| tree-sitter-cli | Parser compiler for nvim-treesitter | GitHub releases |
| starship | Cross-shell prompt | install script |
| jq | JSON processor | apt |

### Neovim plugins

| Plugin | Purpose |
|--------|---------|
| lazy.nvim | Plugin manager |
| catppuccin | Theme (mocha, transparent background) |
| telescope.nvim + fzf-native | Fuzzy finder for files, grep, git |
| oil.nvim | File explorer (edit filesystem like a buffer) |
| gitsigns.nvim | Inline git blame, hunk staging/navigation |
| vim-fugitive | Git commands (`:Git`, diff splits, log) |
| nvim-treesitter | Syntax highlighting (0.12 API) |
| nvim-treesitter-context | Sticky function/class context at top |
| mason.nvim + mason-lspconfig | LSP server installer (pyright, ts_ls) |
| blink.cmp | Completion (LSP, path, snippets, buffer) |
| trouble.nvim | Diagnostics panel |
| snacks.nvim | Bigfile protection + LSP word highlighting |
| vim-tmux-navigator | Seamless tmux/nvim pane switching |
| lualine.nvim | Statusline (branch, diff, diagnostics) |
| nvim-surround | Surround motions (ys, cs, ds) |
| nvim-autopairs | Auto-close brackets/quotes |
| ts-comments.nvim | Treesitter-aware comment strings |
| which-key.nvim | Keybinding discovery (press Space and wait) |
| indent-blankline.nvim | Indent guides with scope highlighting |
| vim-mustache-handlebars | Handlebars syntax for .hbs files |
| friendly-snippets | Snippet collection for blink.cmp |

### Git config

Set globally by `install.sh`:

| Setting | Value | Why |
|---------|-------|-----|
| `core.pager` | delta | Side-by-side diffs everywhere |
| `core.editor` | nvim | |
| `diff.algorithm` | histogram | Cleaner diffs for refactored code |
| `diff.colorMoved` | default | Highlights moved code blocks |
| `merge.conflictstyle` | zdiff3 | Shows original text in conflicts |
| `rerere.enabled` | true | Remembers conflict resolutions |
| `rebase.autosquash` | true | `--fixup` commits auto-reorder |
| `rebase.autostash` | true | Auto-stash before rebase |
| `pull.rebase` | true | Avoids accidental merge commits |
| `push.autoSetupRemote` | true | No more `--set-upstream` on first push |
| `fetch.prune` | true | Removes stale remote tracking refs |
| `commit.verbose` | true | Shows diff in commit editor |
| `branch.sort` | -committerdate | Most recent branches first |

Git aliases: `fixup`, `amend`, `uncommit`, `dw` (word diff), `recent`.

---

## File layout

```
~/
├── .tmux.conf                              -> tmux config
├── .config/
│   ├── nvim/init.lua                       -> neovim config (single file)
│   ├── lazygit/config.yml                  -> lazygit config
│   ├── starship.toml                       -> prompt config
│   ├── terminal-dev-setup/aliases.zsh      -> shell aliases (sourced by .zshrc)
│   └── tmux/plugins/catppuccin/tmux/       -> catppuccin tmux theme
├── .zshrc                                  -> Oh My Zsh + plugins + source line
├── .zshrc.local                            -> machine-specific overrides (create manually)
├── .claude/settings.json                   -> Claude Code settings
├── .tmux/plugins/tpm/                      -> tmux plugin manager
└── .oh-my-zsh/custom/plugins/
    ├── zsh-autosuggestions/                 -> fish-like suggestions as you type
    └── zsh-syntax-highlighting/            -> colors commands green/red as you type
```

## Gotchas

- **fzf in zsh**: Uses `fzf --zsh`, not `--bash`. The `frg` function is
  named to avoid collision with zsh's built-in alias expansion.
- **Telescope treesitter preview**: Disabled (`treesitter = false`) to
  avoid a compatibility issue with the ft_to_lang shim.
- **Lualine theme**: Set to `"auto"`, not `"catppuccin"`, to avoid
  load-order issues.
- **Catppuccin tmux**: Installed manually (not via TPM) to avoid
  documented name conflicts. Update with `git -C ~/.config/tmux/plugins/catppuccin/tmux pull`.
- **TPM plugins**: Press `prefix + I` inside tmux on first run to
  install resurrect, continuum, and yank.
- **Nerd Font required**: Set your terminal font to "JetBrainsMono Nerd
  Font" for icons in Starship prompt, lazygit, and lualine.
