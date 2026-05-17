-- =============================================================================
-- init.lua — Neovim 0.12+ config for terminal-first dev workflow
-- Focused on: code navigation, git, and Python/JS (Zulip stack)
-- =============================================================================

-- Leader key = Space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- =============================================================================
-- Options
-- =============================================================================
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8

opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

opt.splitright = true
opt.splitbelow = true
opt.wrap = false
opt.termguicolors = true
opt.updatetime = 250
opt.timeoutlen = 300
opt.undofile = true
opt.swapfile = false
opt.clipboard = "unnamedplus"
opt.mouse = "a"
opt.showmode = false           -- Shown in statusline instead

-- Session persistence: what :mksession writes. persistence.nvim auto-saves
-- on exit and auto-restores on launch (per cwd). "terminal" keeps terminal
-- *buffers* on restore — but the shell processes die with nvim, so the
-- restored buffers are inert until you run something in them again.
opt.sessionoptions = {
    "buffers", "curdir", "folds", "help", "tabpages",
    "winsize", "winpos", "terminal", "localoptions",
}

-- =============================================================================
-- Key mappings (before plugins, so they work even if plugins fail)
-- =============================================================================
local map = vim.keymap.set

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Better window navigation (works with vim-tmux-navigator)
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Move lines in visual mode
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Keep cursor centered
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Quick save
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save" })

-- Quickfix navigation
map("n", "]q", "<cmd>cnext<CR>zz", { desc = "Next quickfix" })
map("n", "[q", "<cmd>cprev<CR>zz", { desc = "Prev quickfix" })

-- Buffer navigation
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprev<CR>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- Terminal: open in a new tab; double-Esc exits terminal mode (the
-- default <C-\><C-n> chord is unmemorable enough that the embedded
-- shell tends to swallow you for the rest of the session).
map("n", "<leader>T", "<cmd>tab term<CR>", { desc = "Terminal in new tab" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Zulip dev shortcuts — each opens its own tab (so the buffers persist
-- and can be jumped to with gt/gT or :tabnext) instead of stacking in
-- the current window.
map("n", "<leader>rd", "<cmd>tab term devenv up<CR>", { desc = "Run: devenv up" })
-- tools/run-dev calls os.setpgrp(); nvim's :term execs it as the session
-- leader, so setpgrp errors with EPERM. zsh (this user's $SHELL) exec-
-- optimizes a single-command subshell, so plain `(cmd)` doesn't fork —
-- the trailing `; :` adds a second statement that defeats the
-- optimization and forces a fork, after which run-dev is a non-leader
-- child and setpgrp succeeds.
map("n", "<leader>rs", "<cmd>tab term (tools/run-dev; :)<CR>", { desc = "Run: tools/run-dev" })

-- Diagnostic navigation (0.12 API: float= is deprecated; use on_jump)
-- ]d/[d: any diagnostic (errors, warnings, hints, info).
-- ]e/[e: errors only — skip past noise from linters/hints.
-- <C-w>d is a Neovim built-in that opens the line's diagnostics in
-- a float without moving the cursor.
local function open_float_after_jump(d) if d then vim.diagnostic.open_float() end end
map("n", "]d", function() vim.diagnostic.jump({ count = 1, on_jump = open_float_after_jump }) end, { desc = "Next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, on_jump = open_float_after_jump }) end, { desc = "Prev diagnostic" })
map("n", "]e", function() vim.diagnostic.jump({ count = 1, on_jump = open_float_after_jump, severity = vim.diagnostic.severity.ERROR }) end, { desc = "Next error" })
map("n", "[e", function() vim.diagnostic.jump({ count = -1, on_jump = open_float_after_jump, severity = vim.diagnostic.severity.ERROR }) end, { desc = "Prev error" })

-- Smart "go to definition":
--   1. Ask the LSP. If multiple results, prefer real source over .pyi stubs.
--   2. One result -> jump. Many -> populate quickfix and open it.
--   3. No LSP attached / no result -> Telescope grep for the word so you
--      always land somewhere useful, even in lua/bash/handlebars buffers
--      that have no language server.
local function smart_definition()
    local word = vim.fn.expand("<cword>")
    local function fallback_grep()
        if word == "" then
            -- Empty <cword> (cursor on whitespace) → grep_string with ""
            -- would dump every line in the project. Open live_grep instead
            -- so the user can type what they actually want.
            require("telescope.builtin").live_grep()
        else
            require("telescope.builtin").grep_string({ search = word })
        end
    end

    local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" })
    if #clients == 0 then
        fallback_grep()
        return
    end

    local client = clients[1]
    local enc = client.offset_encoding
    local params = vim.lsp.util.make_position_params(0, enc)

    vim.lsp.buf_request_all(0, "textDocument/definition", params, function(results)
        local locations = {}
        for _, res in pairs(results) do
            local r = res and res.result
            if r then
                if r.uri or r.targetUri then
                    locations[#locations + 1] = r
                else
                    for _, loc in ipairs(r) do
                        locations[#locations + 1] = loc
                    end
                end
            end
        end

        if #locations == 0 then
            fallback_grep()
            return
        end

        -- Prefer real source over type stubs when pyright returns both.
        local function is_stub(loc)
            local uri = loc.uri or loc.targetUri or ""
            return uri:match("%.pyi$") ~= nil
        end
        local real = vim.tbl_filter(function(l) return not is_stub(l) end, locations)
        local final = (#real > 0) and real or locations

        if #final == 1 then
            vim.lsp.util.show_document(final[1], enc, { focus = true })
        else
            vim.fn.setqflist({}, " ", {
                title = "LSP definitions",
                items = vim.lsp.util.locations_to_items(final, enc),
            })
            vim.cmd("botright copen")
        end
    end)
end

map("n", "gd", smart_definition, { desc = "Smart go to definition (LSP -> grep)" })

-- Handlebars syntax highlight support
vim.filetype.add({
    extension = {
        hbs = "handlebars",
    },
})

-- =============================================================================
-- Plugin manager: lazy.nvim (auto-installs)
-- =============================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
    vim.fn.system({ "rm", "-rf", lazypath })
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Resolve the repo's base branch for branch-relative git views
-- (<leader>gl, <leader>gd). Prefers upstream/main for forked repos.
local function base_branch()
    local function has_ref(ref)
        vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref })
        return vim.v.shell_error == 0
    end
    local base = (has_ref("upstream/main") and "upstream/main")
        or (has_ref("origin/main") and "origin/main")
        or (has_ref("origin/master") and "origin/master")
    if not base then
        vim.notify(
            "No upstream/main, origin/main, or origin/master found",
            vim.log.levels.ERROR
        )
    end
    return base
end

-- =============================================================================
-- Plugins
-- =============================================================================
require("lazy").setup({

    -- =========================================================================
    -- Theme
    -- =========================================================================
    { "projekt0n/github-nvim-theme", name = "github-theme", priority = 1000 },

    -- =========================================================================
    -- Handlebars
    -- =========================================================================
    {
        "mustache/vim-mustache-handlebars",
        ft = "handlebars",
    },

    -- =========================================================================
    -- Navigation: Telescope (fuzzy finder for everything)
    -- =========================================================================
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
            -- VSCode-style Quick-Open: merges find_files with a frecency
            -- history (recent + most-used files float to the top), with
            -- filename-vs-path weighting that fzf-native alone doesn't do.
            {
                "danielfalk/smart-open.nvim",
                branch = "0.2.x",
                dependencies = {
                    { "kkharji/sqlite.lua" },
                    { "nvim-tree/nvim-web-devicons" },
                },
            },
        },
        config = function()
            local telescope = require("telescope")
            local actions = require("telescope.actions")

            -- Search-time ignore list. Honored automatically by fd (which
            -- auto-loads $XDG_CONFIG_HOME/fd/ignore), and passed explicitly
            -- to rg below. NOT a git-level ignore — git is unaffected.
            local picker_ignore = vim.fn.expand("~/.config/fd/ignore")

            local function count_ignore_patterns()
                local f = io.open(picker_ignore, "r")
                if not f then return 0 end
                local n = 0
                for line in f:lines() do
                    local s = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if s ~= "" and not s:match("^#") then n = n + 1 end
                end
                f:close()
                return n
            end

            local function title_with_ignore(label)
                local n = count_ignore_patterns()
                if n == 0 then
                    return label .. "  (no ignores — <leader>fi to add)"
                end
                return string.format("%s  (ignoring %d patterns — <leader>fi to edit)", label, n)
            end

            telescope.setup({
                defaults = {
                    preview = {
                        treesitter = false,
                    },
                    layout_strategy = "horizontal",
                    layout_config = { prompt_position = "top" },
                    sorting_strategy = "ascending",
                    -- hidden=true / --hidden below makes fd/rg show dotfiles,
                    -- but they then also descend into .git/. Drop those
                    -- entries (objects, refs, hooks, etc.) from every picker.
                    file_ignore_patterns = { "^%.git/", "/%.git/", "^%.git$" },
                    mappings = {
                        i = {
                            ["<C-j>"] = actions.move_selection_next,
                            ["<C-k>"] = actions.move_selection_previous,
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                            ["<M-t>"] = actions.select_tab,
                            -- Wrapped in a closure so trouble.nvim isn't
                            -- require()d eagerly when telescope's config
                            -- runs (it's lazy on cmd="Trouble"); the
                            -- require fires only when <C-t> is pressed.
                            ["<C-t>"] = function(...)
                                return require("trouble.sources.telescope").open(...)
                            end,
                        },
                        n = {
                            ["<M-t>"] = actions.select_tab,
                            ["<C-t>"] = function(...)
                                return require("trouble.sources.telescope").open(...)
                            end,
                        },
                    },
                },
                pickers = {
                    find_files = { hidden = true },
                    live_grep = {
                        additional_args = function()
                            local args = { "--hidden" }
                            if vim.uv.fs_stat(picker_ignore) then
                                table.insert(args, "--ignore-file=" .. picker_ignore)
                            end
                            return args
                        end,
                    },
                },
                extensions = {
                    smart_open = {
                        match_algorithm = "fzf",
                        filename_first = true,
                        cwd_only = true,
                    },
                },
            })
            telescope.load_extension("fzf")
            telescope.load_extension("smart_open")

            local builtin = require("telescope.builtin")

            -- Primary picker: smart_open ranks by frecency + filename match,
            -- like VSCode's Ctrl+P. Plain find_files is still available on
            -- <leader>fF (also bypasses ignores — escape hatch when you
            -- *do* want to find a `*.po` you've ignored).
            local function smart_open()
                require("telescope").extensions.smart_open.smart_open({
                    prompt_title = title_with_ignore("Smart Open"),
                })
            end
            local function find_files_all()
                builtin.find_files({
                    prompt_title = "Find files (no ignore — every file)",
                    no_ignore = true,
                    hidden = true,
                })
            end
            local function live_grep_all()
                builtin.live_grep({
                    prompt_title = "Live grep (no ignore — every file)",
                    additional_args = function() return { "--hidden", "--no-ignore" } end,
                })
            end
            local function edit_picker_ignore()
                vim.cmd("vsplit " .. vim.fn.fnameescape(picker_ignore))
            end

            -- Multi-grep panel: a persistent right-side vertical split
            -- (~30% width) with three live-filtered inputs (Search / Files
            -- glob / Ignore glob) and a results pane that groups matches
            -- by file. The split stays open until the user closes it; results
            -- open in the leftmost editor window without dismissing the panel.
            --
            -- Layout (real :vsplit, not floating):
            --   ┌─ right 30% ────┐
            --   │ Search » ...   │  (3-line input buffer, virt_text labels)
            --   │ Files  » ...   │
            --   │ Ignore » ...   │
            --   ├────────────────┤
            --   │ results buffer │  (grouped by file, readonly)
            --   └────────────────┘
            --
            -- Keybindings (inside the panel):
            --   <Tab> / <S-Tab>  cycle Search → Files → Ignore → Results
            --   <CR> in input    run search and jump focus to results
            --   <CR> / o on a    open file at line in the left pane (panel stays)
            --     match line
            --   <CR> / o on a    toggle fold for that file or folder
            --     header / folder
            --   zc / za          close / toggle fold under cursor. Pressed
            --                    repeatedly from a match line, this folds
            --                    the file → its parent folder → grandparent
            --                    → ... up the tree.
            --   zo / zO          open one level / open recursively at cursor
            --   zM               collapse everything to top-level folders
            --   zR               expand all
            --   j / k in results jump to next/previous match (skip headers)
            --   <LeftMouse>      click any input line to focus it; click a
            --                    header/folder to toggle its fold; click a
            --                    match to open the file
            --   <C-q>            push every match into the quickfix list and
            --                    open it (panel stays so you can keep iterating)
            --   <Esc> / <C-c>    close the panel from any panel buffer
            --   q (normal mode)  close the panel
            --
            -- Persistence:
            --   * Ignore field → ~/.local/state/nvim/multi-grep-ignore (survives restarts)
            --   * Files field  → in-memory, keyed by cwd (sticky per-repo, lost on quit)
            --   * Search field → not persisted (fresh on every open)
            --
            -- Filter syntax (Files / Ignore fields):
            --   actions             plain substring on file path
            --                         (zerver/actions/x.py passes;
            --                          zerver/foo/x.py fails)
            --   *.ts                shell-style glob; * = any chars,
            --                         ? = single char. Anchors are inferred:
            --                         "*.ts" matches paths ending in .ts;
            --                         "src/*" matches paths starting with src/;
            --                         "*foo*" matches paths containing foo.
            --   re:^src/.*\.ts$     escape-hatch vim-regex on file path
            -- Tokens are whitespace-separated; mix freely. Files = include
            -- (any token must match); Ignore = exclude (any match drops it).
            -- Leading '!' on a bare/glob token is stripped (paste-from-
            -- gitignore tolerated).
            -- Tunables. Pulled to the top so the magic numbers aren't
            -- scattered across run_search / open_panel / save logic.
            local MG = {
                REFRESH_DEBOUNCE_MS     = 80,   -- keystroke → rg launch
                IGNORE_SAVE_DEBOUNCE_MS = 250,  -- keystroke → disk write
                POST_CR_FOCUS_DELAY_MS  = 50,   -- <CR>: give rg a beat to populate
                PANEL_WIDTH_FRACTION    = 0.30, -- fraction of editor width
                PANEL_MIN_WIDTH         = 30,   -- clamp for narrow terminals
                INPUT_LINES             = 3,    -- Search / Files / Ignore
            }

            local ignore_state_file = vim.fn.stdpath("state") .. "/multi-grep-ignore"

            local function load_persistent_ignore()
                local f = io.open(ignore_state_file, "r")
                if not f then return "" end
                local s = (f:read("*a") or ""):gsub("[\r\n]+$", "")
                f:close()
                return s
            end
            local function save_persistent_ignore(s)
                vim.fn.mkdir(vim.fn.fnamemodify(ignore_state_file, ":h"), "p")
                local f = io.open(ignore_state_file, "w")
                if f then f:write(s); f:close() end
            end
            -- Session-scoped: the Files filter is sticky within an nvim
            -- session (so reopening the panel keeps your last scope) but
            -- not persisted to disk — Ignore is the disk-persisted one.
            -- Keyed by cwd so a filter set in one repo doesn't silently
            -- carry over to an unrelated checkout.
            local last_include_by_cwd = {}
            local function cwd_key() return vim.uv.cwd() or "" end

            -- Debounced disk write for the Ignore pattern. TextChangedI fires
            -- once per keystroke; without this we'd open() the state file on
            -- every char.
            local ignore_save_timer
            local function schedule_save_ignore(s)
                if ignore_save_timer then pcall(ignore_save_timer.stop, ignore_save_timer) end
                ignore_save_timer = vim.defer_fn(function() save_persistent_ignore(s) end, MG.IGNORE_SAVE_DEBOUNCE_MS)
            end

            -- Module-level singleton: the panel state. nil when closed.
            local panel = nil
            local mg_ns = vim.api.nvim_create_namespace("multi_grep")
            -- Labels surface persistence semantics so the user doesn't have
            -- to remember which field is per-cwd vs disk-backed.
            local mg_labels = { "Search", "Files (cwd)", "Ignore (saved)" }

            -- Highlights: links so the colorscheme drives the look.
            vim.api.nvim_set_hl(0, "MultiGrepLabel",  { link = "Comment",        default = true })
            vim.api.nvim_set_hl(0, "MultiGrepHeader", { link = "Title",          default = true })
            vim.api.nvim_set_hl(0, "MultiGrepFolder", { link = "Directory",      default = true })
            vim.api.nvim_set_hl(0, "MultiGrepLnum",   { link = "LineNr",         default = true })
            vim.api.nvim_set_hl(0, "MultiGrepInfo",   { link = "DiagnosticHint", default = true })
            -- The matched text within each result line. IncSearch reads
            -- correctly as "this is what your query hit" and inherits the
            -- colorscheme's emphasis without us needing to pick a fg/bg.
            vim.api.nvim_set_hl(0, "MultiGrepMatch",  { link = "IncSearch",      default = true })

            local function find_target_window()
                -- Leftmost non-floating window in the CURRENT TAB only —
                -- nvim_list_wins() crosses tabs, which would jump focus
                -- (and open files) into the wrong tab.
                local leftmost, leftmost_col = nil, math.huge
                for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    local cfg = vim.api.nvim_win_get_config(w)
                    if cfg.relative == "" and (not panel
                            or (w ~= panel.input_win and w ~= panel.results_win)) then
                        local pos = vim.api.nvim_win_get_position(w)
                        if pos[2] < leftmost_col then
                            leftmost, leftmost_col = w, pos[2]
                        end
                    end
                end
                return leftmost
            end

            local function close_panel()
                if not panel then return end
                -- Pop out of insert mode BEFORE closing windows. The panel
                -- auto-enters insert mode in the input buffer (via
                -- focus_input_line's startinsert), and vim treats mode as
                -- editor-global state. Closing the panel windows alone
                -- doesn't change the mode — focus lands back in the user's
                -- previous window still in insert mode, which is jarring
                -- since they triggered <leader>fg from normal mode. A
                -- plain `stopinsert` is a no-op when already in normal
                -- mode (e.g. closing from results_buf), so it's always safe.
                vim.cmd("stopinsert")
                -- Final flush of Ignore in case the debounce didn't fire.
                if ignore_save_timer then pcall(ignore_save_timer.stop, ignore_save_timer) end
                if vim.api.nvim_buf_is_valid(panel.input_buf) then
                    local lines = vim.api.nvim_buf_get_lines(panel.input_buf, 0, -1, false)
                    save_persistent_ignore(lines[3] or "")
                end
                if panel.refresh_timer then pcall(panel.refresh_timer.stop, panel.refresh_timer) end
                if panel.current_job then pcall(panel.current_job.kill, panel.current_job, "sigterm") end
                pcall(vim.api.nvim_win_close, panel.input_win, true)
                pcall(vim.api.nvim_win_close, panel.results_win, true)
                pcall(vim.api.nvim_del_augroup_by_id, panel.augroup)
                panel = nil
                _G._multigrep_panel = nil
            end

            -- Files / Ignore fields support three token shapes:
            --   actions      plain substring on the file path
            --   *.ts         shell-style glob (anchored: starts/ends with *
            --                turn off the corresponding anchor; ? = any char)
            --   re:^foo$     escape-hatch vim regex
            -- Tokens are whitespace-separated; mix freely. A leading '!' on
            -- a bare/glob token is stripped (paste-from-gitignore tolerated).
            local function glob_to_lua_pattern(tok)
                -- Escape Lua-pattern specials EXCEPT * and ? (we convert
                -- those to wildcards). Backslash-style escapes inside the
                -- char class match literal `(`, `)`, `.`, `+`, `-`, `[`,
                -- `]`, `^`, `$`, `%`.
                local pat = tok:gsub("([%(%)%.%+%-%[%]%^%$%%])", "%%%1")
                pat = pat:gsub("%*", ".*")
                pat = pat:gsub("%?", ".")
                -- Shell-glob anchoring: a leading '*' means "match at any
                -- prefix" (so don't anchor to start); a trailing '*' means
                -- "match at any suffix" (so don't anchor to end). Bare
                -- patterns like `src/*` anchor to start; `*.ts` anchors to
                -- end.
                if tok:sub(1, 1)  ~= "*" then pat = "^" .. pat end
                if tok:sub(-1)    ~= "*" then pat = pat .. "$" end
                return pat
            end

            local function partition_filter(s)
                local subs, globs, regexes = {}, {}, {}
                for tok in (s or ""):gmatch("%S+") do
                    if tok:sub(1, 3) == "re:" then
                        local pat = tok:sub(4)
                        if pat ~= "" then table.insert(regexes, pat) end
                    elseif tok ~= "" then
                        tok = tok:gsub("^!+", "")
                        if tok ~= "" then
                            if tok:find("[*?]") then
                                table.insert(globs, glob_to_lua_pattern(tok))
                            else
                                table.insert(subs, tok)
                            end
                        end
                    end
                end
                return subs, globs, regexes
            end

            -- Returns (compiled regexes, list of patterns that failed to
            -- compile). Failed patterns get surfaced in the results pane so
            -- the user knows why their filter "did nothing" instead of being
            -- silently dropped.
            local function compile_regexes(patterns)
                local out, bad = {}, {}
                for _, p in ipairs(patterns) do
                    local ok, re = pcall(vim.regex, p)
                    if ok then table.insert(out, re) else table.insert(bad, p) end
                end
                return out, bad
            end

            -- Apply Files (include) and Ignore (exclude) filters to rg's
            -- result entries. Each side has 3 token kinds: substring
            -- (string.find with plain), glob (Lua pattern from
            -- glob_to_lua_pattern), and vim regex. Include = entry must
            -- match at least one token across all kinds; exclude = entry
            -- is dropped if it matches any token. Empty sides short-circuit.
            local function any_match(f, subs, globs, regexes)
                for _, s in ipairs(subs) do
                    if f:find(s, 1, true) then return true end
                end
                for _, p in ipairs(globs) do
                    if f:find(p) then return true end
                end
                for _, re in ipairs(regexes) do
                    if re:match_str(f) then return true end
                end
                return false
            end
            local function apply_path_filter(entries, inc, exc)
                local has_inc = #inc.subs > 0 or #inc.globs > 0 or #inc.regexes > 0
                local has_exc = #exc.subs > 0 or #exc.globs > 0 or #exc.regexes > 0
                if not has_inc and not has_exc then return entries end
                local out = {}
                for _, e in ipairs(entries) do
                    local f = e.file
                    local pass = (not has_inc) or any_match(f, inc.subs, inc.globs, inc.regexes)
                    if pass and has_exc and any_match(f, exc.subs, exc.globs, exc.regexes) then
                        pass = false
                    end
                    if pass then table.insert(out, e) end
                end
                return out
            end

            -- rg only sees the Search query — Files/Ignore are applied as a
            -- post-filter on the file path so plain substring tokens "just
            -- work" without translating them into rg's gitignore-glob syntax.
            local function build_rg_cmd(query)
                if not query or query == "" then return nil end
                local cmd = { "rg", "--vimgrep", "--smart-case", "--color=never", "--hidden" }
                if vim.uv.fs_stat(picker_ignore) then
                    table.insert(cmd, "--ignore-file=" .. picker_ignore)
                end
                table.insert(cmd, "--")
                table.insert(cmd, query)
                return cmd
            end

            local function parse_rg_output(stdout)
                local entries = {}
                for line in (stdout or ""):gmatch("[^\n]+") do
                    local f, l, c, t = line:match("^([^:]+):(%d+):(%d+):(.*)$")
                    if f then
                        entries[#entries + 1] = {
                            file = f, lnum = tonumber(l),
                            col = tonumber(c), text = t,
                        }
                    end
                end
                return entries
            end

            -- Build a directory tree directly from rg entries. Each path
            -- component becomes a tree level, so src/utils/foo.lua nests
            -- under `src/` → `utils/` → foo.lua; files at the cwd root
            -- attach to the tree root with no parent folder. Returns
            -- (root, file_count) so the caller doesn't have to walk the
            -- tree just to render "N matches in M files".
            local function build_tree(entries)
                local root = { children = {}, files = {} }
                local file_node = {}  -- file path → leaf for O(1) match append
                local file_count = 0
                for _, e in ipairs(entries) do
                    local leaf = file_node[e.file]
                    if not leaf then
                        local rel = vim.fn.fnamemodify(e.file, ":.")
                        local parts = {}
                        for part in rel:gmatch("[^/]+") do parts[#parts + 1] = part end
                        local node = root
                        for i = 1, #parts - 1 do
                            local dir = parts[i]
                            if not node.children[dir] then
                                node.children[dir] = { children = {}, files = {} }
                            end
                            node = node.children[dir]
                        end
                        leaf = { name = parts[#parts] or rel, full = e.file, matches = {} }
                        node.files[#node.files + 1] = leaf
                        file_node[e.file] = leaf
                        file_count = file_count + 1
                    end
                    leaf.matches[#leaf.matches + 1] = e
                end
                return root, file_count
            end

            -- Compute the byte span of the search query inside a match line.
            -- Literal queries (no regex metachars) take the fast path: rg
            -- already gave us the column, span is just #query. For regex
            -- queries we try vim.regex against the suffix starting at col;
            -- if vim's regex flavor disagrees with Rust regex (rare for
            -- bread-and-butter patterns), we fall back to no highlight
            -- rather than guessing. Returns (start, length) in bytes
            -- relative to text, or nil.
            local REGEX_METACHARS = "[%[%]%(%)%.%*%+%?%^%$%|\\%{%}]"
            local function build_match_re(query)
                if query == "" then return nil, true end  -- empty literal
                if not query:find(REGEX_METACHARS) then return nil, true end
                -- Mirror rg's --smart-case: all-lowercase → case-insensitive,
                -- otherwise case-sensitive.
                local prefix = (query:lower() == query) and "\\c" or "\\C"
                local ok, re = pcall(vim.regex, prefix .. query)
                if ok then return re, false end
                return nil, false
            end
            local function match_span(text, col, query, re, is_literal)
                if is_literal then return col - 1, #query end
                if not re then return nil end
                local s, e = re:match_str(text:sub(col))
                if s == 0 and e and e > 0 then return col - 1, e end
                return nil
            end

            -- Walk the tree depth-first, emitting one line per folder, file,
            -- and match. Each entry stores its fold_level so the foldexpr
            -- can answer in O(1) without re-walking the tree. The query is
            -- threaded through so each match entry records the byte span of
            -- the matched text — render_results then highlights it.
            local function render_tree(node, depth, lines, index, query)
                local re, is_literal = build_match_re(query)
                local function emit(n, d)
                    local dir_names = {}
                    for k, _ in pairs(n.children) do dir_names[#dir_names + 1] = k end
                    table.sort(dir_names)
                    for _, name in ipairs(dir_names) do
                        local indent = string.rep("  ", d - 1)
                        lines[#lines + 1] = indent .. name .. "/"
                        index[#lines] = {
                            type = "folder", depth = d, fold_level = d,
                        }
                        emit(n.children[name], d + 1)
                    end
                    table.sort(n.files, function(a, b) return a.name < b.name end)
                    for _, file in ipairs(n.files) do
                        local indent = string.rep("  ", d - 1)
                        lines[#lines + 1] = indent .. file.name .. "  (" .. #file.matches .. ")"
                        index[#lines] = {
                            type = "header", depth = d, fold_level = d,
                            file = file.full,
                        }
                        local match_indent = string.rep("  ", d)
                        local lnum_end_col = #match_indent + 8  -- "  %5d " = 8 bytes
                        local text_offset = #match_indent + 12  -- + " │ " (5 bytes)
                        for _, m in ipairs(file.matches) do
                            lines[#lines + 1] = string.format("%s  %5d │ %s",
                                match_indent, m.lnum, m.text)
                            local entry = {
                                type = "match", depth = d + 1,
                                fold_level = d + 1,
                                file = m.file, lnum = m.lnum, col = m.col, text = m.text,
                                lnum_end_col = lnum_end_col,
                            }
                            local s, len = match_span(m.text, m.col, query, re, is_literal)
                            if s then
                                entry.match_start = text_offset + s
                                entry.match_end   = text_offset + s + len
                            end
                            index[#lines] = entry
                        end
                    end
                end
                emit(node, depth)
            end

            local function render_results(entries, opts)
                if not panel or not vim.api.nvim_buf_is_valid(panel.results_buf) then return end
                opts = opts or {}
                local total = #entries
                local query = opts.query or ""
                local lines, index = {}, {}

                if total == 0 then
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = opts.empty_query and "  (type a search term)" or "  (no matches)"
                    if opts.bad_regex and #opts.bad_regex > 0 then
                        lines[#lines + 1] = ""
                        lines[#lines + 1] = "  invalid regex: " .. table.concat(opts.bad_regex, ", ")
                    end
                else
                    local tree, file_count = build_tree(entries)
                    lines[#lines + 1] = string.format("  %d match%s in %d file%s",
                        total, total == 1 and "" or "es",
                        file_count, file_count == 1 and "" or "s")
                    lines[#lines + 1] = ""
                    render_tree(tree, 1, lines, index, query)
                end

                -- Skip the buffer write (and the fold reset that follows)
                -- when the new render is byte-identical to the last one.
                -- Without this, every keystroke that doesn't actually change
                -- the result set still nukes the user's manually-closed folds
                -- via the `zR` below — making `zc` to fold a noisy file
                -- useless mid-search. Fingerprint is just the joined lines:
                -- O(N) hash, but buf_set_lines is O(N) too, so no net cost.
                local fingerprint = table.concat(lines, "\n")
                if panel.last_fingerprint == fingerprint then return end
                panel.last_fingerprint = fingerprint

                vim.bo[panel.results_buf].modifiable = true
                vim.api.nvim_buf_set_lines(panel.results_buf, 0, -1, false, lines)
                vim.bo[panel.results_buf].modifiable = false
                panel.index = index

                vim.api.nvim_buf_clear_namespace(panel.results_buf, mg_ns, 0, -1)
                -- Info line (line 1) when there are matches.
                if total > 0 then
                    vim.api.nvim_buf_set_extmark(panel.results_buf, mg_ns, 0, 0, {
                        end_row = 0, end_col = #lines[1],
                        hl_group = "MultiGrepInfo",
                    })
                end
                -- Per-entry highlights from the tree-built index.
                for ln, e in pairs(index) do
                    if e.type == "folder" then
                        vim.api.nvim_buf_set_extmark(panel.results_buf, mg_ns, ln - 1, 0, {
                            end_row = ln - 1, end_col = #lines[ln],
                            hl_group = "MultiGrepFolder",
                        })
                    elseif e.type == "header" then
                        vim.api.nvim_buf_set_extmark(panel.results_buf, mg_ns, ln - 1, 0, {
                            end_row = ln - 1, end_col = #lines[ln],
                            hl_group = "MultiGrepHeader",
                        })
                    elseif e.type == "match" then
                        -- Highlight the indented "  %5d " prefix only.
                        -- end_col is depth*2 + 8 — never overruns since we
                        -- computed it from the same indent we wrote.
                        vim.api.nvim_buf_set_extmark(panel.results_buf, mg_ns, ln - 1, 0, {
                            end_row = ln - 1, end_col = e.lnum_end_col or 8,
                            hl_group = "MultiGrepLnum",
                        })
                        -- Highlight the matched text within the line. Span
                        -- comes from render_tree (literal: rg's column +
                        -- #query; regex: vim.regex re-match against the
                        -- text suffix at col). Clamp end to the buffer line
                        -- so a regex that matched into a CR doesn't overrun.
                        if e.match_start and e.match_end then
                            local line_len = #lines[ln]
                            local me = math.min(e.match_end, line_len)
                            if me > e.match_start then
                                vim.api.nvim_buf_set_extmark(panel.results_buf, mg_ns, ln - 1, e.match_start, {
                                    end_row = ln - 1, end_col = me,
                                    hl_group = "MultiGrepMatch",
                                })
                            end
                        end
                    end
                end

                -- Folds are computed by a foldexpr that reads panel.index.
                -- This is O(visible) per redraw, vs the previous manual-fold
                -- rebuild that ran one ":fold" per file group on every
                -- keystroke. zx forces re-evaluation after the new lines
                -- land; zR re-opens any folds the user closed during a
                -- prior search so a fresh result set isn't ambushed by
                -- stale closed folds.
                if vim.api.nvim_win_is_valid(panel.results_win) then
                    pcall(vim.api.nvim_win_call, panel.results_win, function()
                        vim.cmd("silent! normal! zx")
                        vim.cmd("silent! normal! zR")
                    end)
                end
            end

            -- foldexpr: each folder/header opens a fold at its tree depth
            -- (1 for top-level folders, 2 for first-level files or
            -- subfolders, ...). Match lines stay inside the parent file
            -- fold via their numeric fold_level. With cursor on a match,
            -- pressing zc closes the file fold; pressing zc again from the
            -- closed-fold line closes the parent folder fold; and so on
            -- up the tree — that's the "fold current file then folder
            -- and so on" behavior. Globals because foldexpr can only call
            -- through v:lua — the panel singleton is exposed via _G.
            function _G._multigrep_foldexpr(lnum)
                local p = _G._multigrep_panel
                if not p or not p.index then return 0 end
                local entry = p.index[lnum]
                if not entry then return 0 end
                if entry.type == "folder" or entry.type == "header" then
                    return ">" .. entry.fold_level
                end
                if entry.type == "match" then
                    return entry.fold_level
                end
                return 0
            end

            -- Custom fold text: keep the file header visible, hint at how
            -- many matches are hidden underneath.
            function _G._multigrep_foldtext()
                local s = vim.v.foldstart
                local e = vim.v.foldend
                local line = vim.fn.getline(s) or ""
                return "▸ " .. line:gsub("^%s*(.-)%s*$", "%1") .. "    [" .. (e - s) .. " hidden]"
            end

            local function run_search()
                if not panel then return end
                local lines = vim.api.nvim_buf_get_lines(panel.input_buf, 0, -1, false)
                local query   = lines[1] or ""
                local include = lines[2] or ""
                local ignore  = lines[3] or ""
                last_include_by_cwd[cwd_key()] = include
                schedule_save_ignore(ignore)

                local inc_subs, inc_globs, inc_regexes = partition_filter(include)
                local exc_subs, exc_globs, exc_regexes = partition_filter(ignore)
                local inc_re, inc_bad = compile_regexes(inc_regexes)
                local exc_re, exc_bad = compile_regexes(exc_regexes)
                local bad = {}
                for _, b in ipairs(inc_bad) do table.insert(bad, "re:" .. b) end
                for _, b in ipairs(exc_bad) do table.insert(bad, "re:" .. b) end
                local inc = { subs = inc_subs, globs = inc_globs, regexes = inc_re }
                local exc = { subs = exc_subs, globs = exc_globs, regexes = exc_re }

                local cmd = build_rg_cmd(query)
                if not cmd then
                    render_results({}, { empty_query = true, bad_regex = bad, query = query })
                    return
                end

                -- Files/Ignore are pure post-filters on rg's output. If the
                -- search query (and cwd) haven't changed since the last rg
                -- run, skip the spawn entirely and re-filter the cached
                -- entries — narrowing the Files glob is then instant on big
                -- repos instead of triggering a fresh rg launch per char.
                local cache_key = cwd_key() .. "\0" .. query
                if panel.last_rg_key == cache_key and panel.last_rg_entries then
                    local entries = apply_path_filter(panel.last_rg_entries, inc, exc)
                    render_results(entries, { bad_regex = bad, query = query })
                    return
                end

                -- Stale-job race guard: a kill()ed rg may still flush its
                -- buffered stdout and call back. Stamp a sequence number on
                -- each launch so a late callback that doesn't match the
                -- current one drops its result on the floor instead of
                -- overwriting newer output.
                if panel.current_job then pcall(panel.current_job.kill, panel.current_job, "sigterm") end
                panel.search_seq = (panel.search_seq or 0) + 1
                local my_seq = panel.search_seq
                panel.current_job = vim.system(cmd, { text = true }, function(result)
                    vim.schedule(function()
                        if not panel or panel.search_seq ~= my_seq then return end
                        local raw = parse_rg_output(result.stdout)
                        panel.last_rg_key     = cache_key
                        panel.last_rg_entries = raw
                        local entries = apply_path_filter(raw, inc, exc)
                        render_results(entries, { bad_regex = bad, query = query })
                    end)
                end)
            end

            local function schedule_refresh()
                if not panel then return end
                if panel.refresh_timer then pcall(panel.refresh_timer.stop, panel.refresh_timer) end
                panel.refresh_timer = vim.defer_fn(function()
                    if panel then run_search() end
                end, MG.REFRESH_DEBOUNCE_MS)
            end

            -- (Re-)anchor the inline label virt_texts at rows 0/1/2. Called
            -- on panel open and any time the input buffer is normalized — if
            -- the user `dd`'s a line, the extmarks for rows 1/2 collapse onto
            -- the surviving row and you get "Search » Files (cwd) » Ignore
            -- (saved) »" all stacked on line 1.
            local function place_input_labels(buf)
                vim.api.nvim_buf_clear_namespace(buf, mg_ns, 0, -1)
                for i, label in ipairs(mg_labels) do
                    vim.api.nvim_buf_set_extmark(buf, mg_ns, i - 1, 0, {
                        virt_text = { { label .. " » ", "MultiGrepLabel" } },
                        virt_text_pos = "inline",
                        right_gravity = false,
                    })
                end
            end

            -- Restore the 3-row layout after the user changed the line
            -- count. The previous normalize_input_buf re-padded blindly
            -- at the end, which made `dd` on Files visually become
            -- "Ignore content jumped to Files": after `dd`, line 2 was
            -- gone and line 3 (Ignore) had shifted up to row 2; padding
            -- then added an empty row at the end, so the Ignore content
            -- visibly "moved" to the Files slot.
            --
            -- restore_layout uses on_lines metadata (firstline = where
            -- the change started) to insert empty rows back AT the
            -- deletion site, so surviving content keeps its row identity.
            -- For multi-line paste we drop excess from the end (the
            -- edit's anchor row is preserved).
            --
            -- Modifying the buffer here re-fires on_lines; fixing_layout
            -- guards against that recursion.
            local function restore_layout(firstline)
                if not panel or not vim.api.nvim_buf_is_valid(panel.input_buf) then
                    return
                end
                if panel.fixing_layout then return end
                panel.fixing_layout = true
                local cur = vim.api.nvim_buf_line_count(panel.input_buf)
                if cur < MG.INPUT_LINES then
                    local pad = {}
                    for _ = 1, MG.INPUT_LINES - cur do pad[#pad + 1] = "" end
                    pcall(vim.api.nvim_buf_set_lines,
                        panel.input_buf, firstline, firstline, false, pad)
                elseif cur > MG.INPUT_LINES then
                    pcall(vim.api.nvim_buf_set_lines,
                        panel.input_buf, MG.INPUT_LINES, -1, false, {})
                end
                place_input_labels(panel.input_buf)
                panel.fixing_layout = false
                panel.restore_pending = false
            end

            -- Final guard: if on_lines isn't going to repair the row
            -- count (no restore pending and the attach somehow missed
            -- the change), bring the buffer back to 3 rows by blind
            -- padding/truncation. We MUST skip this when a restore is
            -- already scheduled — otherwise it runs first (TextChanged
            -- fires before the scheduled tick) and pads at the END,
            -- defeating the row-aware restore. Worst case here: after
            -- a multi-step edit normalize re-anchors at the wrong row;
            -- the on_lines path fixes the common cases.
            local function normalize_input_buf()
                if not panel or not vim.api.nvim_buf_is_valid(panel.input_buf) then return end
                if panel.restore_pending or panel.fixing_layout then return end
                local lines = vim.api.nvim_buf_get_lines(panel.input_buf, 0, -1, false)
                if #lines == MG.INPUT_LINES then return end
                while #lines < MG.INPUT_LINES do lines[#lines + 1] = "" end
                while #lines > MG.INPUT_LINES do table.remove(lines) end
                vim.api.nvim_buf_set_lines(panel.input_buf, 0, -1, false, lines)
                place_input_labels(panel.input_buf)
            end

            -- Snapshot all match entries from panel.index into the quickfix
            -- list and open it. Lets the user push a finished search out of
            -- the live panel and into a stable list they can navigate with
            -- ]q / [q while editing — the panel itself stays open so they
            -- can keep iterating on the search.
            local function send_to_quickfix()
                if not panel or not panel.index then return end
                local items = {}
                -- panel.index is a sparse table keyed by lnum, but matches
                -- arrive in document order, so a numeric for-loop preserves
                -- the on-screen order in the quickfix list.
                local total = vim.api.nvim_buf_line_count(panel.results_buf)
                for ln = 1, total do
                    local e = panel.index[ln]
                    if e and e.type == "match" then
                        items[#items + 1] = {
                            filename = e.file, lnum = e.lnum,
                            col = e.col, text = e.text,
                        }
                    end
                end
                if #items == 0 then
                    vim.notify("multi-grep: no matches to send to quickfix", vim.log.levels.WARN)
                    return
                end
                local query = vim.api.nvim_buf_get_lines(panel.input_buf, 0, 1, false)[1] or ""
                vim.fn.setqflist({}, " ", {
                    title = "multi-grep: " .. query,
                    items = items,
                })
                vim.cmd("botright copen")
            end

            -- <CR>/o on a folder or file header toggles its fold; on a
            -- match it opens the file in the leftmost window.
            local function activate_under_cursor()
                if not panel or not vim.api.nvim_win_is_valid(panel.results_win) then return end
                local row = vim.api.nvim_win_get_cursor(panel.results_win)[1]
                local entry = panel.index[row]
                if not entry then return end
                if entry.type == "folder" or entry.type == "header" then
                    vim.api.nvim_win_call(panel.results_win, function() vim.cmd("normal! za") end)
                    return
                end
                if entry.type ~= "match" then return end
                local target = find_target_window()
                if target then
                    vim.api.nvim_set_current_win(target)
                else
                    -- No left target (panel is the only window, or only
                    -- floats are open). topleft vsplit creates a new window
                    -- at the editor's left edge — NOT inside the panel
                    -- column, which `aboveleft vsplit` from input_win would
                    -- have done, narrowing the panel each invocation.
                    vim.cmd("topleft vsplit")
                end
                vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
                pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, math.max((entry.col or 1) - 1, 0) })
                vim.cmd("normal! zz")
            end

            local function jump_match(direction)
                if not panel then return end
                local row = vim.api.nvim_win_get_cursor(panel.results_win)[1]
                local total = vim.api.nvim_buf_line_count(panel.results_buf)
                local i = row + direction
                while i >= 1 and i <= total do
                    if panel.index[i] and panel.index[i].type == "match" then
                        vim.api.nvim_win_set_cursor(panel.results_win, { i, 0 })
                        return
                    end
                    i = i + direction
                end
            end

            local function focus_input_line(n)
                if not panel or not vim.api.nvim_win_is_valid(panel.input_win) then return end
                if not vim.api.nvim_buf_is_valid(panel.input_buf) then return end
                pcall(vim.api.nvim_set_current_win, panel.input_win)
                pcall(vim.api.nvim_win_set_cursor, panel.input_win,
                    { n, #(vim.api.nvim_buf_get_lines(panel.input_buf, n - 1, n, false)[1] or "") })
                vim.cmd("startinsert!")
            end

            local function focus_results()
                if not panel or not vim.api.nvim_win_is_valid(panel.results_win) then return end
                vim.cmd("stopinsert")
                pcall(vim.api.nvim_set_current_win, panel.results_win)
                -- Land on the first actual match if cursor is on a header/info line.
                local row = vim.api.nvim_win_get_cursor(panel.results_win)[1]
                if not panel.index[row] or panel.index[row].type ~= "match" then
                    jump_match(1)
                end
            end

            local function tab_cycle(direction)
                if not panel then return end
                local cur_buf = vim.api.nvim_get_current_buf()
                if cur_buf == panel.input_buf then
                    local row = vim.api.nvim_win_get_cursor(panel.input_win)[1]
                    local nxt = row + direction
                    if nxt >= 1 and nxt <= MG.INPUT_LINES then
                        focus_input_line(nxt)
                    else
                        focus_results()
                    end
                elseif cur_buf == panel.results_buf then
                    focus_input_line(direction == 1 and 1 or MG.INPUT_LINES)
                end
            end

            local function open_panel(opts)
                opts = opts or {}
                if panel and vim.api.nvim_win_is_valid(panel.input_win) then
                    -- Already open: refocus and replace Search with the new
                    -- default (e.g. a fresh <leader>fs cword). Treat the
                    -- keystroke as "start a new search," not "merge into
                    -- whatever's there."
                    if opts.default_text and opts.default_text ~= "" then
                        vim.api.nvim_buf_set_lines(panel.input_buf, 0, 1, false, { opts.default_text })
                        schedule_refresh()
                    end
                    focus_input_line(1)
                    return
                end

                local original_win = vim.api.nvim_get_current_win()

                -- Real right-side vertical split, ~30% of editor width
                -- (clamped to a usable minimum on narrow terminals).
                -- Critical: split horizontally BEFORE resizing the input
                -- window down to 3 rows. With no horizontal sibling at the
                -- moment of resize, vim has nowhere to absorb the slack and
                -- shrinks the editor's effective height instead.
                vim.cmd("botright vsplit")
                local width = math.max(MG.PANEL_MIN_WIDTH,
                    math.floor(vim.o.columns * MG.PANEL_WIDTH_FRACTION))
                vim.cmd("vertical resize " .. width)
                vim.cmd("belowright split")
                -- After belowright split, focus is on the new BOTTOM window.
                local results_win = vim.api.nvim_get_current_win()
                vim.cmd("wincmd k")
                local input_win = vim.api.nvim_get_current_win()

                local input_buf = vim.api.nvim_create_buf(false, true)
                vim.bo[input_buf].buftype = "nofile"
                vim.bo[input_buf].swapfile = false
                vim.bo[input_buf].bufhidden = "wipe"
                vim.bo[input_buf].filetype = "multigrep_input"

                vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, {
                    opts.default_text or "",
                    last_include_by_cwd[cwd_key()] or "",
                    load_persistent_ignore(),
                })
                vim.api.nvim_win_set_buf(input_win, input_buf)

                place_input_labels(input_buf)

                -- Now safe: results_win exists below, will absorb the slack.
                vim.api.nvim_win_set_height(input_win, MG.INPUT_LINES)
                vim.wo[input_win].winfixheight = true
                vim.wo[input_win].winfixwidth = true
                vim.wo[input_win].number = false
                vim.wo[input_win].relativenumber = false
                vim.wo[input_win].cursorline = false
                vim.wo[input_win].wrap = false
                vim.wo[input_win].signcolumn = "no"
                vim.wo[input_win].statusline = "%#StatusLineNC# multi-grep ─ <Tab> next · <CR> results · <C-q> qflist · q close"

                local results_buf = vim.api.nvim_create_buf(false, true)
                vim.bo[results_buf].buftype = "nofile"
                vim.bo[results_buf].swapfile = false
                vim.bo[results_buf].bufhidden = "wipe"
                vim.bo[results_buf].filetype = "multigrep_results"
                vim.bo[results_buf].modifiable = false
                vim.api.nvim_win_set_buf(results_win, results_buf)
                vim.wo[results_win].number = false
                vim.wo[results_win].relativenumber = false
                vim.wo[results_win].cursorline = true
                vim.wo[results_win].wrap = false
                vim.wo[results_win].winfixwidth = true
                vim.wo[results_win].signcolumn = "no"
                vim.wo[results_win].statusline = "%#StatusLineNC# results ─ j/k next · <CR>/o open · zc fold · zM all · <C-q> qflist · <Tab> inputs"

                local augroup = vim.api.nvim_create_augroup(
                    "multi_grep_panel_" .. input_buf, { clear = true })

                panel = {
                    input_buf = input_buf, input_win = input_win,
                    results_buf = results_buf, results_win = results_win,
                    original_win = original_win,
                    index = {},
                    augroup = augroup,
                    -- last_fingerprint: hash of the previous render's lines.
                    -- Used by render_results to short-circuit no-op redraws
                    -- and preserve user fold state across same-result
                    -- keystrokes.
                    last_fingerprint = nil,
                }
                -- Expose the panel singleton via _G so foldexpr (called
                -- from Vim through v:lua) can reach panel.index.
                _G._multigrep_panel = panel

                -- Configure folds once on the results window — foldexpr
                -- recomputes per-line on demand from panel.index, so we
                -- never have to rebuild folds on each refresh.
                vim.wo[results_win].foldmethod = "expr"
                vim.wo[results_win].foldexpr = "v:lua._multigrep_foldexpr(v:lnum)"
                vim.wo[results_win].foldtext = "v:lua._multigrep_foldtext()"
                vim.wo[results_win].foldlevel = 99
                vim.wo[results_win].fillchars = "fold: "

                -- Seed an initial render so the results buffer isn't empty —
                -- some plugins (satellite.nvim) misbehave when a buffer they
                -- attach to has zero lines.
                render_results({})

                -- DirChanged: re-seed the Files line from the new cwd's
                -- sticky scope so the displayed glob matches what
                -- last_include_by_cwd[cwd_key()] actually holds (otherwise
                -- the visible glob would be from the prior cwd, but
                -- run_search would key the *current* cwd, polluting it).
                vim.api.nvim_create_autocmd("DirChanged", {
                    group = augroup,
                    callback = function()
                        if not panel or not vim.api.nvim_buf_is_valid(panel.input_buf) then return end
                        local glob = last_include_by_cwd[cwd_key()] or ""
                        vim.api.nvim_buf_set_lines(panel.input_buf, 1, 2, false, { glob })
                        schedule_refresh()
                    end,
                })

                vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
                    group = augroup, buffer = input_buf,
                    callback = function()
                        -- on_lines does the row-aware restore; this just
                        -- catches anything that slipped past, then kicks
                        -- the search.
                        normalize_input_buf()
                        schedule_refresh()
                    end,
                })

                -- Row-aware layout restore. on_lines fires synchronously
                -- AFTER each buffer modification with metadata about which
                -- rows changed; we use it to put empty rows back at the
                -- exact deletion site instead of blindly padding at the
                -- end (which mis-attributes content to fields). Without
                -- this, `dd` on Files makes Ignore appear in the Files
                -- slot. Modifying the buffer from inside on_lines is
                -- forbidden by textlock — vim.schedule defers the fix-up
                -- to the next tick. The restore_pending flag tells
                -- normalize_input_buf to stay out of the way until the
                -- scheduled restore has run; otherwise normalize runs
                -- first (from the synchronous TextChanged) and end-pads,
                -- which is what we're trying to avoid.
                vim.api.nvim_buf_attach(input_buf, false, {
                    on_lines = function(_, buf, _, firstline, lastline, new_lastline, _)
                        if not panel or panel.input_buf ~= buf then return true end  -- detach
                        if panel.fixing_layout then return end
                        if lastline ~= new_lastline then
                            -- Line count changed — restore_layout will
                            -- pad/truncate using `firstline` as the
                            -- insertion site for empty rows. The
                            -- delta size is recoverable from
                            -- buf_line_count at restore time, so we
                            -- only need firstline here.
                            panel.restore_pending = true
                            vim.schedule(function() restore_layout(firstline) end)
                        end
                    end,
                })

                -- Defensive: tear down the panel if either of our buffers
                -- gets wiped externally.
                vim.api.nvim_create_autocmd("BufWipeout", {
                    group = augroup, buffer = input_buf,
                    callback = function() vim.schedule(close_panel) end,
                })
                vim.api.nvim_create_autocmd("BufWipeout", {
                    group = augroup, buffer = results_buf,
                    callback = function() vim.schedule(close_panel) end,
                })

                -- Input keymaps
                vim.keymap.set({ "i", "n" }, "<Tab>",   function() tab_cycle(1)  end, { buffer = input_buf, silent = true })
                vim.keymap.set({ "i", "n" }, "<S-Tab>", function() tab_cycle(-1) end, { buffer = input_buf, silent = true })
                vim.keymap.set({ "i", "n" }, "<CR>",    function()
                    -- Run the search synchronously and jump to results.
                    run_search()
                    -- Give vim.system a beat to populate before jumping.
                    vim.defer_fn(focus_results, MG.POST_CR_FOCUS_DELAY_MS)
                end, { buffer = input_buf, silent = true })
                vim.keymap.set({ "i", "n" }, "<C-c>",   close_panel, { buffer = input_buf, silent = true })
                -- <Esc> closes from both modes — single-press dismissal is
                -- the muscle memory ("back out"). Also bind `q` in normal
                -- so closing from input matches the results-buffer affordance.
                vim.keymap.set({ "i", "n" }, "<Esc>",   close_panel, { buffer = input_buf, silent = true })
                vim.keymap.set("n",          "q",       close_panel, { buffer = input_buf, silent = true })
                vim.keymap.set({ "i", "n" }, "<C-u>",   function()
                    -- Clear just the current line.
                    local row = vim.api.nvim_win_get_cursor(panel.input_win)[1]
                    vim.api.nvim_buf_set_lines(panel.input_buf, row - 1, row, false, { "" })
                    schedule_refresh()
                end, { buffer = input_buf, silent = true })
                vim.keymap.set({ "i", "n" }, "<C-q>", send_to_quickfix, { buffer = input_buf, silent = true })

                -- Prevent insert-mode edits that would join two input lines
                -- and silently shift the field labels. The 3-row layout is
                -- structural; once a line break disappears, Ignore visually
                -- becomes Files (and so on) — normalize_input_buf re-pads
                -- to 3 lines but can't reconstruct which content belonged
                -- on which row. So we swallow BS / <C-w> at column 0 and
                -- <Del> at end-of-line. (vim's 'backspace' option would
                -- block this globally, but it's not buffer-local.)
                local function at_line_start()
                    return vim.api.nvim_win_get_cursor(panel.input_win)[2] == 0
                end
                local function at_line_end()
                    local row, col = unpack(vim.api.nvim_win_get_cursor(panel.input_win))
                    local line = vim.api.nvim_buf_get_lines(panel.input_buf, row - 1, row, false)[1] or ""
                    return col >= #line
                end
                -- The previous version used expr=true and returned the BS
                -- keycode bytes from the callback. That re-fed those bytes
                -- through the mapping pipeline, which re-triggered THIS
                -- mapping; after recursion was detected vim fell back to
                -- inserting the raw bytes as text (the user saw "<80>kb"
                -- — BS's internal representation — appearing in the input
                -- field). Using nvim_feedkeys with mode "n" (no-remap)
                -- queues a single, un-remapped key into the typeahead, so
                -- default BS / Del / etc. processing fires without ever
                -- looping back through our buffer-local map.
                local function guarded(at_blocking, key)
                    return function()
                        if at_blocking() then return end  -- swallow
                        vim.api.nvim_feedkeys(
                            vim.api.nvim_replace_termcodes(key, true, false, true),
                            "n", false)
                    end
                end
                local guard_opts = { buffer = input_buf, silent = true }
                vim.keymap.set("i", "<BS>",  guarded(at_line_start, "<BS>"),  guard_opts)
                vim.keymap.set("i", "<C-h>", guarded(at_line_start, "<C-h>"), guard_opts)
                vim.keymap.set("i", "<C-w>", guarded(at_line_start, "<C-w>"), guard_opts)
                vim.keymap.set("i", "<Del>", guarded(at_line_end,   "<Del>"), guard_opts)
                -- Normal-mode line-count-changing commands. The 3-row
                -- layout is structural; o/O would push fields off the
                -- bottom, J/gJ would merge two fields. on_lines repairs
                -- damage from `dd` / Vd / paste, but `o`/`O`/`J`/`gJ`
                -- have intent that doesn't translate to a single-row
                -- field, so we just no-op them. (J in particular would
                -- otherwise leave Files empty and the joined content in
                -- the Ignore slot.)
                local nop_opts = { buffer = input_buf, silent = true }
                vim.keymap.set("n", "o",  "<Nop>", nop_opts)
                vim.keymap.set("n", "O",  "<Nop>", nop_opts)
                vim.keymap.set("n", "J",  "<Nop>", nop_opts)
                vim.keymap.set("n", "gJ", "<Nop>", nop_opts)

                -- Mouse on the input buffer: <LeftMouse> default-positions
                -- the cursor; we hook <LeftRelease> to (re-)enter insert
                -- mode at the click position. Bound for both modes so
                -- clicking from outside (n) or from within (i) works.
                vim.keymap.set({ "n", "i" }, "<LeftRelease>", function()
                    local m = vim.fn.getmousepos()
                    if m.winid ~= panel.input_win then return end
                    pcall(vim.api.nvim_set_current_win, panel.input_win)
                    pcall(vim.api.nvim_win_set_cursor, panel.input_win,
                        { math.max(m.line, 1), math.max(m.column - 1, 0) })
                    if vim.api.nvim_get_mode().mode ~= "i" then
                        vim.cmd("startinsert")
                    end
                end, { buffer = input_buf, silent = true })

                -- Results keymaps
                vim.keymap.set("n", "<CR>",    activate_under_cursor,           { buffer = results_buf, silent = true })
                vim.keymap.set("n", "o",       activate_under_cursor,           { buffer = results_buf, silent = true })
                vim.keymap.set("n", "<Tab>",   function() tab_cycle(1)  end, { buffer = results_buf, silent = true })
                vim.keymap.set("n", "<S-Tab>", function() tab_cycle(-1) end, { buffer = results_buf, silent = true })
                vim.keymap.set("n", "j",       function() jump_match(1)  end, { buffer = results_buf, silent = true })
                vim.keymap.set("n", "k",       function() jump_match(-1) end, { buffer = results_buf, silent = true })
                vim.keymap.set("n", "q",       close_panel,              { buffer = results_buf, silent = true })
                vim.keymap.set("n", "<Esc>",   close_panel,              { buffer = results_buf, silent = true })
                vim.keymap.set("n", "<C-c>",   close_panel,              { buffer = results_buf, silent = true })
                vim.keymap.set("n", "<C-q>",   send_to_quickfix,         { buffer = results_buf, silent = true })

                -- Mouse on results: single-click a header → toggle fold;
                -- a match → open file; info/blank lines → no-op.
                -- <LeftMouse> stays default (vim positions the cursor and
                -- still allows <LeftDrag> to build a visual selection for
                -- copy-paste). <LeftRelease> finalizes — but if the user
                -- ended a drag in visual mode, leave it alone.
                --
                -- Bound for both "n" and "i" because the user can land in
                -- the results buffer while still in insert mode: clicking
                -- on the results pane from within the input field's
                -- insert mode triggers vim's default cross-window cursor
                -- move (`:help i_<LeftMouse>`) but does NOT exit insert
                -- mode. Without an insert-mode binding here, the click
                -- would silently leave the user typing into a non-
                -- modifiable buffer ("E21: Cannot make changes,
                -- 'modifiable' is off") and never open the file. The
                -- handler stops insert at the top so subsequent
                -- keypresses behave normally.
                local function on_results_click()
                    -- vim.fn.mode() returns the short form: "i" insert,
                    -- "v"/"V"/"\22" (Ctrl-V) for the three visual modes,
                    -- "n" normal. We use it consistently here so the two
                    -- branches read off the same value.
                    local mode = vim.fn.mode()
                    if mode == "i" then vim.cmd("stopinsert") end
                    if mode == "v" or mode == "V" or mode == "\22" then return end
                    local m = vim.fn.getmousepos()
                    if m.winid ~= panel.results_win or m.line < 1 then return end
                    pcall(vim.api.nvim_set_current_win, panel.results_win)
                    pcall(vim.api.nvim_win_set_cursor, panel.results_win, { m.line, 0 })
                    activate_under_cursor()
                end
                vim.keymap.set({ "n", "i" }, "<LeftRelease>", on_results_click,
                    { buffer = results_buf, silent = true })
                -- Squash double-click word-select on results so a quick
                -- second click doesn't yank you into visual mode mid-flow.
                vim.keymap.set({ "n", "i" }, "<2-LeftMouse>", "<Nop>",
                    { buffer = results_buf, silent = true })

                -- Initial render and focus
                focus_input_line(1)
                schedule_refresh()
            end

            local function multi_grep()
                open_panel({})
            end

            -- True when the current tab is a diffview / fugitive view, not
                -- a normal file-editing tab. Opening the right-side panel into
                -- one of those tabs hijacks the diff layout, so multi_grep_cword
                -- spawns a fresh tab first.
            local function tab_has_special_view()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    local buf = vim.api.nvim_win_get_buf(win)
                    local name = vim.api.nvim_buf_get_name(buf)
                    local ft = vim.bo[buf].filetype
                    if name:match("^diffview://")
                        or name:match("^fugitive://")
                        or ft:match("^Diffview")
                        or ft == "fugitive"
                        or ft == "fugitiveblame"
                        or ft == "git" then
                        return true
                    end
                end
                return false
            end

            local function multi_grep_cword()
                local w = vim.fn.expand("<cword>")
                if tab_has_special_view() then
                    vim.cmd("tabnew")
                end
                open_panel({ default_text = w ~= "" and w or nil })
            end

            map("n", "<C-p>", smart_open, { desc = "Find files (smart)" })
            map("n", "<leader>ff", smart_open, { desc = "Find files (smart)" })
            map("n", "<leader>fF", find_files_all, { desc = "Find files (no ignore)" })
            map("n", "<leader>fg", multi_grep, { desc = "Multi-grep (search / files / ignore)" })
            map("n", "<leader>fG", live_grep_all, { desc = "Live grep (no ignore)" })
            map("n", "<leader>fi", edit_picker_ignore, { desc = "Edit picker-ignore file" })
            map("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            map("n", "<leader>fh", builtin.help_tags, { desc = "Help" })
            map("n", "<leader>fs", multi_grep_cword, { desc = "Multi-grep (cword prefilled)" })
            map("n", "<leader>fo", builtin.oldfiles, { desc = "Recent files" })
            map("n", "<leader>fr", builtin.resume, { desc = "Resume last search" })

            -- Git pickers
            map("n", "<leader>gc", builtin.git_commits, { desc = "Git commits" })
            map("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })
            map("n", "<leader>gs", builtin.git_status, { desc = "Git status" })
        end,
    },

    -- =========================================================================
    -- File tree
    -- =========================================================================
    {
        "stevearc/oil.nvim",
        config = function()
            require("oil").setup({
                view_options = { show_hidden = true },
                keymaps = {
                    ["q"] = "actions.close",
                },
            })
            map("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
        end,
    },

    -- =========================================================================
    -- File tree (tree view with collapse/expand and search)
    -- =========================================================================
    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons",
            "MunifTanjim/nui.nvim",
        },
        keys = {
            { "<leader>t", "<cmd>Neotree toggle<CR>", desc = "File tree" },
            { "<leader>e", "<cmd>Neotree reveal<CR>", desc = "File tree (reveal current)" },
        },
        config = function()
            require("neo-tree").setup({
                filesystem = {
                    filtered_items = {
                        visible = true,
                        hide_dotfiles = false,
                        hide_gitignored = false,
                    },
                    follow_current_file = { enabled = true },
                    use_libuv_file_watcher = true,
                },
                window = {
                    width = 35,
                    mappings = {
                        ["/"] = "fuzzy_finder",
                        ["z"] = "close_all_nodes",
                        ["Z"] = "expand_all_nodes",
                    },
                },
            })
        end,
    },

    -- =========================================================================
    -- Git integration
    -- =========================================================================

    -- Gitsigns: inline blame, hunk actions
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns").setup({
                current_line_blame = true,
                current_line_blame_opts = { delay = 500 },
                on_attach = function(bufnr)
                    -- Don't attach to ephemeral / non-file buffers.
                    -- gitsigns' current-line blame otherwise schedules a
                    -- blame run for these buffers and crashes inside
                    -- run_blame when cache.repo isn't populated:
                    --   blame.lua:228: attempt to index field 'repo'
                    --     (a nil value)
                    -- Returning false from on_attach prevents the
                    -- attach altogether, per `:help gitsigns-config`.
                    local bt = vim.bo[bufnr].buftype
                    if bt ~= "" then return false end  -- nofile / terminal / quickfix / prompt / help / etc.

                    local gs = package.loaded.gitsigns
                    local function bmap(mode, lhs, rhs, desc)
                        map(mode, lhs, rhs, { buffer = bufnr, desc = desc })
                    end

                    -- Hunk navigation
                    bmap("n", "]h", function() gs.nav_hunk("next") end, "Next hunk")
                    bmap("n", "[h", function() gs.nav_hunk("prev") end, "Prev hunk")

                    -- Hunk actions
                    bmap("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
                    bmap("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
                    bmap("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
                    bmap("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line (full)")
                    bmap("n", "<leader>hd", gs.diffthis, "Diff against index")
                    bmap("n", "<leader>hD", function() gs.diffthis("~") end, "Diff against last commit")
                end,
            })
        end,
    },

    -- Fugitive: the gold standard for git in vim
    {
        "tpope/vim-fugitive",
        cmd = { "Git", "Gdiffsplit", "Gvdiffsplit", "Gclog" },
        keys = {
            { "<leader>gg", "<cmd>Git<CR>", desc = "Git status (fugitive)" },
            -- Log / diff of commits ahead of the repo's base branch,
            -- full-screen tab. Picks upstream/main first (forked repos),
            -- then origin/main, then origin/master — whichever exists.
            -- <leader>gd: Diffview of uncommitted changes (working tree + index vs HEAD).
            -- <leader>gD: Diffview of <base>..HEAD (commits ahead of the base branch).
            -- <leader>gl: fugitive log of <base>..HEAD. --decorate annotates
            --   each commit with branch tips that point at it (e.g.
            --   "abc1234 (devenv) Commit msg") so you can see when a commit
            --   is shared with another local branch — fugitive captures into
            --   a buffer, so decorations are off by default and need to be
            --   forced. <CR> on a commit = fugitive's git-show view (use
            --   <C-o> to return). `a` on a commit = Diffview file-tree view
            --   (q closes back to log tab).
            { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Git diff (uncommitted)" },
            {
                "<leader>gD",
                function()
                    local base = base_branch()
                    if not base then return end
                    vim.cmd(("DiffviewOpen %s..HEAD"):format(base))
                end,
                desc = "Git diff <base>..HEAD",
            },
            {
                "<leader>gl",
                function()
                    local base = base_branch()
                    if not base then return end
                    vim.cmd(("tab Git log %s..HEAD --oneline --decorate"):format(base))
                end,
                desc = "Git log <base>..HEAD",
            },
            { "<leader>gL", "<cmd>tab Git log --oneline --all --graph -30<CR>", desc = "Git log graph (all)" },
        },
    },

    -- Diffview: file-tree browser for a commit or diff range, full diffs per file
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
        config = function()
            local actions = require("diffview.actions")

            -- Floating window with the full commit message of the current
            -- diffview view. Bound to L below so it's reachable from the
            -- file panel AND the diff buffers (the virt_lines preview at
            -- the top of the file panel only shows when that pane is focused).
            local function show_commit_msg()
                local ok, lib = pcall(require, "diffview.lib")
                if not ok then return end
                local view = lib.get_current_view()
                local commit = view and view.right and view.right.commit
                if not commit then
                    vim.notify("No commit info for this view", vim.log.levels.WARN)
                    return
                end
                local out = vim.fn.systemlist({
                    "git", "log", "-1", "--format=%h %s%n%n%b", commit,
                })
                if vim.v.shell_error ~= 0 or #out == 0 then return end

                local buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
                vim.bo[buf].modifiable = false
                vim.bo[buf].bufhidden = "wipe"
                vim.bo[buf].filetype = "gitcommit"

                local width  = math.min(80, vim.o.columns - 4)
                local height = math.min(#out, vim.o.lines - 6)
                vim.api.nvim_open_win(buf, true, {
                    relative  = "editor",
                    row       = math.floor((vim.o.lines  - height) / 2),
                    col       = math.floor((vim.o.columns - width)  / 2),
                    width     = width,
                    height    = height,
                    style     = "minimal",
                    border    = "rounded",
                    title     = " Commit message ",
                    title_pos = "center",
                })
                vim.keymap.set("n", "q",     "<cmd>close<CR>", { buffer = buf, nowait = true })
                vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, nowait = true })
            end

            require("diffview").setup({
                -- Show deletions as red on the left pane and dim filler (~)
                -- with no colored bg on the right, instead of vimdiff's default
                -- of green-on-left + red-filler-on-right, which inverts what
                -- "this line was removed" intuitively reads as. Diffview wires
                -- this by remapping DiffAdd→DiffviewDiffAddAsDelete (uses
                -- DiffDelete's red bg) on the left and DiffDelete→
                -- DiffviewDiffDeleteDim (linked to Comment, fg-only) on both
                -- panes' filler lines.
                enhanced_diff_hl = true,
                -- corporate/tests/stripe_fixtures/*.json has `-diff` set in
                -- .gitattributes (so `git diff` prints "Binary files differ"),
                -- which makes Diffview skip loading the file contents and show
                -- an empty diff buffer. Forcing diff_binaries=true bypasses the
                -- is_binary check; Diffview loads both revs as text and runs
                -- nvim's diff over them.
                diff_binaries = true,
                file_panel = {
                    listing_style = "tree",
                    tree_options = { flatten_dirs = true, folder_statuses = "only_folded" },
                    -- Narrower panel (was 35). File list is ~30% slimmer.
                    win_config = { position = "left", width = 25 },
                },
                hooks = {
                    -- Long minified-JSON / one-line markdown diffs scroll
                    -- horizontally off-screen by default. Wrap inside diff
                    -- buffers so the whole change stays visible. wrap is
                    -- window-local, so opt_local set inside the win_enter
                    -- hook applies only to diffview's windows.
                    diff_buf_win_enter = function()
                        vim.opt_local.wrap = true
                        vim.opt_local.linebreak = true
                    end,
                },
                keymaps = {
                    view = {
                        { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                        -- j/k in the diff windows navigates between files in the panel
                        { "n", "<Tab>",   actions.select_next_entry, { desc = "Next changed file" } },
                        { "n", "<S-Tab>", actions.select_prev_entry, { desc = "Prev changed file" } },
                        { "n", "L", show_commit_msg, { desc = "Show commit message" } },
                    },
                    file_panel = {
                        { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                        { "n", "<CR>", actions.select_entry, { desc = "Open file diff" } },
                        { "n", "j", actions.next_entry, { desc = "Next file" } },
                        { "n", "k", actions.prev_entry, { desc = "Prev file" } },
                        { "n", "L", show_commit_msg, { desc = "Show commit message" } },
                    },
                    file_history_panel = {
                        { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
                        { "n", "L", show_commit_msg, { desc = "Show commit message" } },
                    },
                },
            })
        end,
    },

    -- Satellite: VSCode-style scrollbar on the right edge.
    -- Shows cursor position, search matches, diagnostics, gitsigns hunks —
    -- plus a custom handler below that marks &diff change regions, so inside
    -- diffview you can see where all the diffs live and where you are.
    {
        "lewis6991/satellite.nvim",
        lazy = false,
        config = function()
            require("satellite").setup({
                current_only = false,
                -- The scrollbar lives in the rightmost screen column, so with
                -- winblend=0 it fully covers any character that wraps into
                -- that column (Diffview forces wrap → last char of every wrap
                -- segment vanishes). 50 keeps the bar clearly visible while
                -- letting wrapped text show through underneath.
                winblend = 50,
                -- Skip our multi-grep panel buffers — satellite's cursor
                -- handler trips on the nofile/empty-line transitions and
                -- spams "Invalid 'id'" errors.
                excluded_filetypes = { "multigrep_input", "multigrep_results" },
                handlers = {
                    cursor     = { enable = true, symbols = { "⎺", "⎻", "⎼", "⎽" } },
                    search     = { enable = true },
                    diagnostic = { enable = true },
                    gitsigns   = { enable = true },
                    marks      = { enable = false },
                    quickfix   = { enable = true },
                },
            })

            -- Custom handler: light up &diff change regions in the scrollbar.
            -- satellite requires handler.config to be set in setup() — reading
            -- self.config.priority crashes apply_mark otherwise.
            local diff_handler = { name = "diff" }
            function diff_handler.setup(user_cfg)
                diff_handler.config = vim.tbl_deep_extend("force", {
                    enable   = true,
                    priority = 30,
                    overlap  = true,
                }, user_cfg or {})
            end
            function diff_handler.update(bufnr, winid)
                if not vim.api.nvim_win_is_valid(winid) or not vim.wo[winid].diff then
                    return {}
                end
                -- `pos` in marks is a scrollbar-row, not a buffer-line —
                -- util.row_to_barpos maps buffer lines into that space.
                local util = require("satellite.util")
                local marks = {}
                vim.api.nvim_win_call(winid, function()
                    local line_count = vim.api.nvim_buf_line_count(bufnr)
                    for lnum = 1, line_count do
                        local hl = vim.fn.diff_hlID(lnum, 1)
                        if hl ~= 0 then
                            local name = vim.fn.synIDattr(hl, "name")
                            if name ~= "" then
                                marks[#marks + 1] = {
                                    pos       = util.row_to_barpos(winid, lnum - 1),
                                    highlight = name,
                                    symbol    = "█",
                                }
                            end
                        end
                    end
                end)
                return marks
            end
            require("satellite.handlers").register(diff_handler)

            -- Satellite refreshes on BufWinEnter/WinScrolled/etc. but NOT on
            -- DiffUpdated. When diffview swaps files, the buffer loads before
            -- nvim has computed diff hunks, so diff_hlID returns 0 and our marks
            -- come out empty. Trigger a refresh once the diff is ready.
            vim.api.nvim_create_autocmd("DiffUpdated", {
                group = vim.api.nvim_create_augroup("satellite_diff_refresh", { clear = true }),
                callback = function()
                    vim.schedule(function() pcall(vim.cmd, "SatelliteRefresh") end)
                end,
            })
        end,
    },

    -- =========================================================================
    -- Treesitter (Neovim 0.12+ API)
    -- =========================================================================
    {
        "nvim-treesitter/nvim-treesitter",
        -- Pin to the new `main` branch explicitly. `require("nvim-treesitter").install`
        -- and per-FileType `vim.treesitter.start` are the main-branch API; the
        -- `master` branch (still the GitHub default at time of writing) ships a
        -- different module that doesn't expose `install` and would error at config
        -- time. lazy.nvim happens to pick main today, but locking it here makes
        -- that intentional rather than incidental.
        branch = "main",
        lazy = false,
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter").install({
                "python", "javascript", "typescript", "html", "css",
                "json", "yaml", "toml", "bash", "lua", "markdown",
                "markdown_inline", "git_rebase", "gitcommit", "diff",
            })

            -- Enable treesitter highlighting for all filetypes with a parser.
            -- Skip when Snacks has flagged the buffer as bigfile — running
            -- the full parser on a multi-MB minified JS file can lock the
            -- editor for several seconds on each cursor move. snacks.bigfile
            -- marks bigfiles by switching the *filetype* to "bigfile" (not a
            -- buffer variable), so check filetype here.
            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("ts_highlight", { clear = true }),
                callback = function(args)
                    if vim.bo[args.buf].filetype == "bigfile" then return end
                    pcall(vim.treesitter.start)
                end,
            })
        end,
    },

    -- Treesitter: sticky context at top
    {
        "nvim-treesitter/nvim-treesitter-context",
        config = function()
            require("treesitter-context").setup({
                max_lines = 3,
            })
        end,
    },

    -- =========================================================================
    -- LSP (native vim.lsp.config — Neovim 0.11+)
    -- =========================================================================
    {
        "mason-org/mason.nvim",
        dependencies = {
            "mason-org/mason-lspconfig.nvim",
            -- mason-lspconfig 2.x is a thin bridge; the default `cmd`/
            -- root_dir/filetypes for each server live in nvim-lspconfig.
            -- Without it, vim.lsp.enable("pyright") errors with
            -- "cmd: expected function or table, got nil" and no server
            -- ever attaches.
            "neovim/nvim-lspconfig",
        },
        config = function()
            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "pyright",   -- Python types (Zulip backend)
                    -- ruff is installed via Astral's standalone installer
                    -- (~/.local/bin/ruff). Mason's PyPI route needs pip/pipx,
                    -- which isn't on this box; vim.lsp.enable() below still
                    -- picks up the on-PATH binary.
                    "ts_ls",     -- TypeScript / JavaScript
                    "eslint",    -- JS/TS lint — reads Zulip's .eslintrc.*
                    "lua_ls",    -- Lua (this very init.lua)
                    "bashls",    -- Bash (shell scripts in dotfiles)
                    "marksman",  -- Markdown (hud.md, READMEs)
                },
            })
        end,
    },

    -- =========================================================================
    -- Completion (blink.cmp)
    -- =========================================================================
    {
        "saghen/blink.cmp",
        version = "1.*",
        dependencies = { "rafamadriz/friendly-snippets" },
        opts = {
            keymap = { preset = "default" },
            appearance = { nerd_font_variant = "mono" },
            -- Don't pop completion in the multi-grep input field — it's a
            -- search box, not code, and the menu fights with TextChanged.
            enabled = function()
                return vim.bo.filetype ~= "multigrep_input"
            end,
            completion = {
                documentation = {
                    auto_show = true,
                    auto_show_delay_ms = 500,
                },
                list = {
                    selection = {
                        preselect = true,
                        auto_insert = true,
                    },
                },
            },
            signature = { enabled = true },
            sources = {
                default = { "lsp", "path", "snippets", "buffer" },
            },
            fuzzy = { implementation = "prefer_rust_with_warning" },
        },
        opts_extend = { "sources.default" },
    },

    -- =========================================================================
    -- Diagnostics panel
    -- =========================================================================
    {
        "folke/trouble.nvim",
        cmd = "Trouble",
        keys = {
            { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "Diagnostics" },
            { "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Buffer diagnostics" },
            { "<leader>xl", "<cmd>Trouble loclist toggle<CR>", desc = "Location list" },
            { "<leader>xq", "<cmd>Trouble qflist toggle<CR>", desc = "Quickfix list" },
        },
        opts = {
            modes = {
                telescope = {
                    sort = { "filename", "pos" },
                    groups = {
                        { "directory", format = " {directory_icon}{directory} " },
                        { "filename", format = " {file_icon}{filename} " },
                    },
                },
            },
        },
    },

    -- =========================================================================
    -- Snacks: bigfile + word highlighting
    -- =========================================================================
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            -- Zulip ships some large generated/minified files (vendor
            -- JS, test fixtures). Snacks bigfile sets vim.b.bigfile and
            -- disables LSP, syntax, indent guides, gitsigns, etc. so
            -- those buffers stay snappy. Default is 1.5 MB; 1 MB is a
            -- better cutoff for this repo.
            bigfile = { enabled = true, size = 1024 * 1024 },
            words = { enabled = true },
        },
        keys = {
            -- jump(count, cycle): pass vim.v.count1 so a [count] prefix actually
            -- advances by that many references rather than always one.
            { "]]", function() Snacks.words.jump(vim.v.count1, true) end, desc = "Next LSP reference" },
            { "[[", function() Snacks.words.jump(-vim.v.count1, true) end, desc = "Prev LSP reference" },
        },
    },

    -- =========================================================================
    -- Tmux integration
    -- =========================================================================
    {
        "christoomey/vim-tmux-navigator",
        lazy = false,
    },

    -- =========================================================================
    -- Quality of life
    -- =========================================================================
    {
        "nvim-lualine/lualine.nvim",
        config = function()
            require("lualine").setup({
                options = {
                    theme = "auto",
                    component_separators = "|",
                    section_separators = "",
                    -- The multi-grep panel sets per-window statuslines that
                    -- explain the keybindings; let those stand instead of
                    -- having lualine repaint them.
                    disabled_filetypes = {
                        statusline = { "multigrep_input", "multigrep_results" },
                    },
                },
                sections = {
                    lualine_b = { "branch", "diff", "diagnostics" },
                    lualine_c = { { "filename", path = 1 } },  -- Relative path
                },
            })
        end,
    },

    -- Surround: ys, cs, ds motions
    { "kylechui/nvim-surround", event = "VeryLazy", config = true },

    -- Autopairs
    { "windwp/nvim-autopairs", event = "InsertEnter", config = true },

    -- Treesitter-aware comment strings (Handlebars, embedded languages)
    { "folke/ts-comments.nvim", opts = {}, event = "VeryLazy" },

    -- Which-key: shows available keybindings
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        config = function()
            local wk = require("which-key")
            -- delay must be < timeoutlen (300ms above) — otherwise vim
            -- cancels the partial chord before which-key gets a chance
            -- to draw the popup. 200ms is the upstream default and
            -- leaves a 100ms window for the popup to be visible.
            wk.setup({ delay = 200 })
            wk.add({
                { "<leader>f", group = "Find" },
                { "<leader>g", group = "Git" },
                { "<leader>h", group = "Hunks" },
                { "<leader>b", group = "Buffer" },
                { "<leader>x", group = "Diagnostics" },
                { "<leader>r", group = "Run" },
                { "<leader>q", group = "Session" },
                -- Note: <leader>t is the Neotree toggle (a direct keymap,
                -- not a prefix), so no group entry for it — declaring one
                -- would label the leaf action with the group name.
            })
        end,
    },

    -- =========================================================================
    -- Session persistence — auto-save on exit, auto-restore on launch.
    -- One session per cwd, stored under stdpath("state")/sessions/. Open
    -- nvim with no file args in a directory that has a saved session and
    -- it restores buffers, tabs, window layout, cursor positions, folds.
    -- Manual: <leader>qs (load last for cwd), <leader>ql (load last anywhere),
    -- <leader>qd (stop saving for this session — exit won't overwrite).
    -- =========================================================================
    {
        "folke/persistence.nvim",
        -- lazy=false because (a) save is registered in setup() via a
        -- VimLeavePre autocmd that must exist before exit, and (b) the
        -- VimEnter autoload below has to be wired up before VimEnter fires.
        lazy = false,
        config = function()
            require("persistence").setup()
            -- DiffView and fugitive log/diff buffers are produced by running
            -- git commands at view time; their contents aren't backed by a
            -- file on disk, so :mksession only records the bufname. On
            -- restore the windows come back empty. Wipe these buffers (and
            -- close any DiffView tab cleanly) before save so they aren't in
            -- the session at all — reopen with <leader>gd / :Git as needed.
            -- persistence.nvim fires User PersistenceSavePre right before it
            -- runs :mksession, which is the hook point we want.
            vim.api.nvim_create_autocmd("User", {
                pattern = "PersistenceSavePre",
                group = vim.api.nvim_create_augroup("persistence_clean_git_bufs", { clear = true }),
                callback = function()
                    pcall(vim.cmd, "DiffviewClose")
                    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                        if vim.api.nvim_buf_is_valid(buf) then
                            local name = vim.api.nvim_buf_get_name(buf)
                            local ft = vim.bo[buf].filetype
                            if name:match("^diffview://")
                                or name:match("^fugitive://")
                                or ft:match("^Diffview")
                                or ft == "fugitive"
                                or ft == "fugitiveblame"
                                or ft == "git" then
                                pcall(vim.api.nvim_buf_delete, buf, { force = true })
                            end
                        end
                    end
                end,
            })
            -- persistence.nvim auto-saves but doesn't auto-load. Restore
            -- the cwd's session when nvim launches with no file args (and
            -- nothing on stdin), so `nvim` in a project just resumes.
            local group = vim.api.nvim_create_augroup("persistence_autoload", { clear = true })
            vim.api.nvim_create_autocmd("StdinReadPre", {
                group = group,
                callback = function() vim.g.started_with_stdin = true end,
            })
            vim.api.nvim_create_autocmd("VimEnter", {
                group = group,
                nested = true,
                once = true,
                callback = function()
                    if vim.fn.argc(-1) == 0 and not vim.g.started_with_stdin then
                        require("persistence").load()
                    end
                end,
            })
        end,
        keys = {
            { "<leader>qs", function() require("persistence").load() end, desc = "Restore session for cwd" },
            { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
            { "<leader>qd", function() require("persistence").stop() end, desc = "Stop session save on exit" },
        },
    },

    -- Indent guides
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        config = function()
            require("ibl").setup({
                indent = { char = "│" },
                scope = { enabled = true },
            })
        end,
    },

}, {
    -- lazy.nvim options
    checker = { enabled = false },  -- Don't auto-check for updates
    change_detection = { notify = false },
})

-- =============================================================================
-- LSP config (native Neovim 0.11+)
-- =============================================================================
-- Walk up from `root` looking for a binary inside a nix devenv-managed
-- venv/profile. Lets pyright/ruff use the project's own interpreter +
-- linter (matching Zulip's exact dependency set + rule version) without
-- requiring nvim to be launched from inside `devenv shell`.
local function devenv_bin_from(root, name)
    local cur = root
    while cur and cur ~= "/" and cur ~= "" do
        for _, sub in ipairs({
            "/.devenv/state/venv/bin/",
            "/.devenv/profile/bin/",
        }) do
            local p = cur .. sub .. name
            if vim.uv.fs_stat(p) then return p end
        end
        local parent = vim.fn.fnamemodify(cur, ":h")
        if parent == cur then break end
        cur = parent
    end
end

-- True if `root` looks like it's actively configured for pyright —
-- either a pyrightconfig.json or a [tool.pyright] section in
-- pyproject.toml. Used to decide whether pyright's diagnostics should
-- be trusted; in projects that use mypy + ruff (e.g. Zulip), pyright
-- runs with stock defaults and surfaces checks like reportPossibly-
-- Unbound that the project's actual CI never enforces — pure editor
-- noise.
local function project_uses_pyright(root)
    if vim.uv.fs_stat(root .. "/pyrightconfig.json") then return true end
    local f = io.open(root .. "/pyproject.toml")
    if not f then return false end
    local s = f:read("*a")
    f:close()
    return s:find("%[tool%.pyright") ~= nil
end

-- pyright: Zulip's repo is large enough that the default "workspace"
-- diagnosticMode walks every .py file on attach and chews through CPU
-- + RAM. "openFilesOnly" only analyzes buffers I have open; goto-def /
-- hover / completion still work because pyright lazy-loads the rest.
-- before_init also points pythonPath at the devenv interpreter, and
-- silences pyright's type-check diagnostics in projects that don't
-- opt into pyright (Zulip uses mypy + ruff; pyright defaults flag
-- false positives like reportPossiblyUnbound that mypy never raises).
vim.lsp.config("pyright", {
    settings = {
        python = {
            analysis = {
                diagnosticMode = "openFilesOnly",
                useLibraryCodeForTypes = true,
                autoSearchPaths = true,
            },
        },
    },
    before_init = function(_, config)
        local root = config.root_dir or vim.fn.getcwd()
        config.settings = config.settings or {}
        config.settings.python = config.settings.python or {}
        config.settings.python.analysis = config.settings.python.analysis or {}

        local py = devenv_bin_from(root, "python")
        if py then
            config.settings.python.pythonPath = py
        end

        if not project_uses_pyright(root) then
            -- Keep navigation/hover/completion; drop the noisy default
            -- type-check diagnostics. The project's real linter (ruff)
            -- and type checker (mypy in CI) remain authoritative.
            config.settings.python.analysis.typeCheckingMode = "off"
        end
    end,
})
-- ruff: reads [tool.ruff] from Zulip's pyproject.toml automatically,
-- so the editor surfaces the exact same select/ignore lists that CI
-- enforces. cmd is a function so we can swap the binary to the
-- project's own ruff (when devenv manages one) at spawn time, matching
-- Zulip's exact ruff version. on_new_config from nvim-lspconfig's
-- legacy API is silently ignored by Neovim's native vim.lsp.config —
-- using the cmd-function form is the supported equivalent.
vim.lsp.config("ruff", {
    cmd = function(dispatchers, config)
        local root = (config and config.root_dir) or vim.fn.getcwd()
        local bin = devenv_bin_from(root, "ruff") or "ruff"
        return vim.lsp.rpc.start({ bin, "server" }, dispatchers)
    end,
})
-- ts_ls: Zulip's web/ TS project is large; the default 3 GB tsserver
-- heap gets OOM-killed mid-session. 8 GB is plenty headroom. Reads
-- tsconfig.json automatically.
vim.lsp.config("ts_ls", {
    init_options = {
        maxTsServerMemory = 8192,
    },
})
-- eslint: reads .eslintrc.* / eslint.config.* from the workspace root,
-- so Zulip's lint rules drive the diagnostics here.
vim.lsp.config("eslint", {})
vim.lsp.config("bashls", {})
vim.lsp.config("marksman", {})
-- lua_ls: teach it about the Neovim API so editing init.lua doesn't
-- light up with "undefined global `vim`" diagnostics. library used to be
-- nvim_get_runtime_file("", true), which dumps every plugin's full tree
-- (~hundreds of MB of telescope/lazy/plenary/etc) into lua_ls's workspace
-- — startup hangs for seconds and RSS climbs into the gigabytes. Just
-- the runtime's lua/ directory is enough for vim.* completion and
-- diagnostics on init.lua.
vim.lsp.config("lua_ls", {
    settings = {
        Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim", "Snacks" } },
            workspace = {
                library = { vim.env.VIMRUNTIME .. "/lua" },
                checkThirdParty = false,
            },
            telemetry = { enable = false },
        },
    },
})
vim.lsp.enable({ "pyright", "ruff", "ts_ls", "eslint", "lua_ls", "bashls", "marksman" })

vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp_attach_keymaps", { clear = true }),
    callback = function(args)
        local bufnr = args.buf
        local function lmap(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
        end
        -- gd is set globally to smart_definition (handles non-LSP buffers,
        -- filters .pyi stubs, opens quickfix on multiple matches).
        lmap("gr", vim.lsp.buf.references, "References")
        lmap("gI", vim.lsp.buf.implementation, "Implementation")
        lmap("K", vim.lsp.buf.hover, "Hover docs")
        lmap("<leader>rn", vim.lsp.buf.rename, "Rename")
        lmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
        lmap("gD", vim.lsp.buf.declaration, "Go to declaration")
        lmap("<leader>D", vim.lsp.buf.type_definition, "Type definition")
    end,
})

-- In fugitive's git log:
--   <CR> → :Git show <hash> in a new tab (git-show-style single buffer)
--   a    → :DiffviewOpen <hash>^! in a new tab (file tree + per-file diffs)
-- Both open new tabs so `q` / :tabc returns to the log tab with cursor preserved.
local git_ft_group = vim.api.nvim_create_augroup("git_ft_setup", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
    group = git_ft_group,
    pattern = "git",
    callback = function()
        local function commit_under_cursor()
            return vim.api.nvim_get_current_line():match("(%x%x%x%x%x%x+)")
        end

        vim.keymap.set("n", "<CR>", function()
            local hash = commit_under_cursor()
            if hash then
                vim.cmd("tab Git show " .. hash)
            else
                vim.notify("No commit hash on this line", vim.log.levels.WARN)
            end
        end, { buffer = true, desc = "Show commit (git show) in new tab" })

        vim.keymap.set("n", "a", function()
            local hash = commit_under_cursor()
            if hash then
                vim.cmd("DiffviewOpen " .. hash .. "^!")
            else
                vim.notify("No commit hash on this line", vim.log.levels.WARN)
            end
        end, { buffer = true, desc = "Open commit in Diffview (file tree)" })

        -- `q` in a :Git show buffer closes the tab back to the log
        vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = true, desc = "Close tab" })

        -- Colorize --oneline log output. Stock syntax/git.vim only matches
        -- the bare hash via gitHashAbbrev → Identifier — nothing for the
        -- "(HEAD -> branch, devenv, tag: v1)" decoration that --decorate
        -- emits, so log lines come out monochrome. Schedule the matches
        -- onto the next tick so they land *after* runtime/syntax/git.vim
        -- finishes loading (FileType fires before Syntax, which sources
        -- the syntax script and would clobber matches added inline here).
        local buf = vim.api.nvim_get_current_buf()
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            vim.api.nvim_buf_call(buf, function()
                vim.cmd([[
                    syntax match fugitiveLogDecoration "([^)]*)" contains=fugitiveLogHEAD,fugitiveLogTag,fugitiveLogRemote
                    syntax match fugitiveLogHEAD       "HEAD\%(\s*->\s*[^,)]\+\)\?" contained
                    syntax match fugitiveLogTag        "tag:[^,)]\+"                contained
                    syntax match fugitiveLogRemote     "\<\h\w*/[^,)]\+"            contained
                    " gitHashAbbrev defaults to Identifier — nearly the same
                    " grey as fg in github-dark. Bump to Type (orange) so the
                    " hash actually stands out.
                    highlight! link gitHashAbbrev                Type
                    highlight default link fugitiveLogDecoration Constant
                    highlight default link fugitiveLogHEAD       Statement
                    highlight default link fugitiveLogTag        Function
                    highlight default link fugitiveLogRemote     String
                ]])
            end)
        end)
    end,
})

-- Disable folds in fugitive/git buffers so diffs open fully expanded
vim.api.nvim_create_autocmd("FileType", {
    group = git_ft_group,
    pattern = { "git", "fugitive", "fugitiveblame", "gitcommit" },
    callback = function()
        vim.opt_local.foldenable = false
        vim.opt_local.foldlevel = 99
    end,
})

-- Show the commit message at the top of Diffview's file panel.
-- Runs whenever a DiffviewFiles buffer is set up. Pulls the active view
-- from diffview's lib and reads the commit SHA off view.right.
local diffview_commit_ns = vim.api.nvim_create_namespace("diffview_commit_msg")
vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("diffview_commit_header", { clear = true }),
    pattern = "DiffviewFiles",
    callback = function(args)
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(args.buf) then return end
            local ok, lib = pcall(require, "diffview.lib")
            if not ok then return end
            local view = lib.get_current_view()
            local commit = view and view.right and view.right.commit
            if not commit then return end

            local out = vim.fn.systemlist({
                "git", "log", "-1", "--format=%h %s%n%n%b", commit,
            })
            if vim.v.shell_error ~= 0 or #out == 0 then return end

            local virt_lines = {}
            for _, line in ipairs(out) do
                virt_lines[#virt_lines + 1] = { { line, "Comment" } }
            end
            virt_lines[#virt_lines + 1] = { { "", "Comment" } }

            vim.api.nvim_buf_clear_namespace(args.buf, diffview_commit_ns, 0, -1)
            vim.api.nvim_buf_set_extmark(args.buf, diffview_commit_ns, 0, 0, {
                virt_lines = virt_lines,
                virt_lines_above = true,
            })
        end)
    end,
})

-- =============================================================================
-- Terminal buffer naming
-- =============================================================================
-- Default terminal buffer names look like "term://<cwd>//<pid>:zsh" — once
-- you have several terminals open, :ls and Telescope's buffer picker can't
-- tell them apart. Rename each one to the program currently running in it
-- (e.g. "term://btop:7") or, when only the shell prompt is up, the basename
-- of the shell's cwd (e.g. "term://terminal-dev-setup:7"). The :<bufnr>
-- suffix keeps names unique so set_name never errors on a collision.
if vim.fn.has("linux") == 1 then
    local function compute_name(bufnr)
        local job_id = vim.b[bufnr].terminal_job_id
        if not job_id then return nil end
        local ok, shell_pid = pcall(vim.fn.jobpid, job_id)
        if not ok or not shell_pid then return nil end

        -- /proc/<pid>/stat: comm is in parens (may contain spaces). Fields
        -- after the closing ") " are state, ppid, pgrp, session, tty_nr,
        -- tpgid (#6) — the foreground process group of the controlling tty.
        local f = io.open("/proc/" .. shell_pid .. "/stat")
        if not f then return nil end
        local stat = f:read("*a")
        f:close()
        local rest = stat and stat:match("%)%s+(.*)$")
        if not rest then return nil end
        local fields = vim.split(rest, " ")
        local tpgid = tonumber(fields[6])

        local function cwd_basename()
            local cwd = vim.uv.fs_readlink("/proc/" .. shell_pid .. "/cwd")
            return cwd and vim.fn.fnamemodify(cwd, ":t") or "term"
        end

        -- tpgid <= 0 or == shell_pid → shell is foreground (just the prompt).
        if not tpgid or tpgid <= 0 or tpgid == shell_pid then
            return cwd_basename()
        end
        local cf = io.open("/proc/" .. tpgid .. "/comm")
        if not cf then return cwd_basename() end
        local comm = cf:read("*l")
        cf:close()
        return (comm and comm ~= "") and comm or cwd_basename()
    end

    local function refresh(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then return false end
        if vim.bo[bufnr].buftype ~= "terminal" then return false end
        local name = compute_name(bufnr)
        if not name then return true end  -- transient /proc miss; keep polling
        local target = ("term://%s:%d"):format(name, bufnr)
        if vim.api.nvim_buf_get_name(bufnr) ~= target then
            pcall(vim.api.nvim_buf_set_name, bufnr, target)
        end
        return true
    end

    vim.api.nvim_create_autocmd("TermOpen", {
        -- Group with clear=true so re-running the autocmd block (rare,
        -- but defensive) doesn't register a second handler that would
        -- spawn a duplicate poll timer per terminal buffer.
        group = vim.api.nvim_create_augroup("term_buf_naming", { clear = true }),
        callback = function(args)
            local bufnr = args.buf
            refresh(bufnr)
            local timer = vim.uv.new_timer()
            timer:start(1500, 1500, vim.schedule_wrap(function()
                if not refresh(bufnr) then
                    timer:stop()
                    if not timer:is_closing() then timer:close() end
                end
            end))
        end,
    })
end

require("github-theme").setup({
    options = {
        transparent = true,
        styles = { comments = "italic" },
    },
})

vim.cmd.colorscheme "github_dark"

-- Subtle diff backgrounds. github_dark's Added/Removed/Changed set a guifg
-- which clobbers syntax tokens inside diff regions, so DiffView shows code as
-- flat green/red. Override the upstream Added/Removed/Changed groups (the
-- chain is DiffAdd → diffAdded → Added) so DiffAdd/DiffDelete/DiffChange keep
-- their links — diffview's setup derives DiffviewDiffAddAsDelete from those
-- links, and replacing DiffAdd with a direct hl breaks that derivation and
-- can paint the entire left pane red. Drop fg, dial bg down.
local function set_subtle_diff_hl()
    vim.api.nvim_set_hl(0, "Added",   { bg = "#19321f" })
    vim.api.nvim_set_hl(0, "Removed", { bg = "#3a1d22" })
    vim.api.nvim_set_hl(0, "Changed", { bg = "#2a2616" })
    -- DiffText is the within-line "this character range changed" emphasis on
    -- top of DiffChange. github_dark sets it directly with both bg AND fg
    -- (#363C44 / #e6edf3) — and unlike DiffAdd/DiffDelete/DiffChange it isn't
    -- routed through the Added/Removed/Changed link chain, so the Changed
    -- override above doesn't reach it. The forced fg flattens syntax tokens
    -- inside the changed range. Re-set bg only (slightly brighter yellow than
    -- Changed so the emphasis still pops) and clear fg so treesitter wins.
    vim.api.nvim_set_hl(0, "DiffText", { bg = "#4a3a18" })
    -- DiffviewDiffAddAsDelete is what enhanced_diff_hl maps the left pane's
    -- "DiffAdd" (= removed lines) to. Diffview computes it via get_bg(
    -- "DiffDelete", no_trans=true) which doesn't follow link chains, so since
    -- DiffDelete → diffRemoved → Removed (link only, no direct bg), diffview
    -- ends up with bg=NONE and the left pane has no red. Set it explicitly to
    -- the same red as Removed so deletions read correctly.
    vim.api.nvim_set_hl(0, "DiffviewDiffAddAsDelete", { bg = "#3a1d22" })
end
set_subtle_diff_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("subtle_diff_hl", { clear = true }),
    callback = set_subtle_diff_hl,
})
-- Diffview is lazy-loaded by :DiffviewOpen, and its setup() calls
-- update_diff_hl() which clobbers DiffviewDiffAddAsDelete back to bg=NONE.
-- Re-apply our override after each DiffView opens so the left-pane red sticks.
vim.api.nvim_create_autocmd("User", {
    pattern = { "DiffviewViewOpened", "DiffviewViewEnter" },
    group = vim.api.nvim_create_augroup("diffview_red_left_pane", { clear = true }),
    callback = function()
        vim.api.nvim_set_hl(0, "DiffviewDiffAddAsDelete", { bg = "#3a1d22" })
    end,
})
