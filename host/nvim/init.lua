-- =============================================================================
-- init.lua — slim host-side Neovim config.
-- Themes + visual chrome + diffview + treesitter highlighting for branch
-- review. No LSP, no oil, no editing helpers.
-- =============================================================================

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
opt.showmode = false

-- :grep goes through git grep (project-scoped, .gitignore-aware).
opt.grepprg = "git --no-pager grep --no-color -n --column"
opt.grepformat = "%f:%l:%c:%m"

opt.sessionoptions = {
    "buffers", "curdir", "folds", "help", "tabpages",
    "winsize", "winpos", "terminal", "localoptions",
}

-- =============================================================================
-- Keymaps
-- =============================================================================
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")

map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save" })

map("n", "]q", "<cmd>cnext<CR>zz", { desc = "Next quickfix" })
map("n", "[q", "<cmd>cprev<CR>zz", { desc = "Prev quickfix" })

map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprev<CR>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

map("n", "<leader>T", "<cmd>tab term<CR>", { desc = "Terminal in new tab" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

map("n", "<leader>ff", ":find ", { desc = "Find file" })

map("n", "<leader>gl", "<cmd>DiffviewOpen main...HEAD<CR>", { desc = "Diffview: branch vs main" })

vim.filetype.add({ extension = { hbs = "handlebars" } })

-- =============================================================================
-- Plugin manager: lazy.nvim (auto-installs on first launch)
-- =============================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

-- Diff highlight groups: vivid GitHub-style backgrounds with NO foreground, so
-- treesitter syntax shows through on changed lines while add/delete/change stay
-- clear. diffview's defaults were a dull, desaturated green/maroon AND carried a
-- fg that flattened the syntax. Re-applied on view-open + colorscheme change.
local function style_diff_hl()
    vim.api.nvim_set_hl(0, "DiffAdd",    { bg = "#1a4d2b" }) -- added lines
    vim.api.nvim_set_hl(0, "DiffText",   { bg = "#2b6f3d" }) -- changed words (emphasis)
    vim.api.nvim_set_hl(0, "DiffChange", { bg = "#16361f" }) -- changed lines
    vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#5e2630" }) -- removed lines / fill
    -- gutter change-bar colors (brighter accents than the line backgrounds)
    vim.api.nvim_set_hl(0, "DiffAddSign",    { fg = "#3fb950" })
    vim.api.nvim_set_hl(0, "DiffChangeSign", { fg = "#d29922" })
    vim.api.nvim_set_hl(0, "DiffDeleteSign", { fg = "#f85149" })
end

-- Gutter change-bar: a colored ▎ in the sign column on every added/changed/
-- removed line of a diff window, so you can see at a glance (and while
-- scrolling) where changes fall across the file. diff_hlID() classifies each
-- line; signs are extmarks scoped to one namespace so they're cheap to redraw.
local diff_sign_ns = vim.api.nvim_create_namespace("diffview_change_signs")
local function place_diff_signs(win)
    if not (win and vim.api.nvim_win_is_valid(win) and vim.wo[win].diff) then return end
    vim.wo[win].signcolumn = "yes"
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_clear_namespace(buf, diff_sign_ns, 0, -1)
    vim.api.nvim_win_call(win, function()
        for l = 1, vim.api.nvim_buf_line_count(buf) do
            local id = vim.fn.diff_hlID(l, 1)
            if id ~= 0 then
                local name = vim.fn.synIDattr(id, "name")
                local hl = name == "DiffDelete" and "DiffDeleteSign"
                    or name == "DiffAdd" and "DiffAddSign"
                    or "DiffChangeSign"
                pcall(vim.api.nvim_buf_set_extmark, buf, diff_sign_ns, l - 1, 0,
                    { sign_text = "▎", sign_hl_group = hl })
            end
        end
    end)
end

-- Single-commit review navigation. The Zed "Browse commit" task sets
-- g:review_commit; [C/]C step to the older parent / newer child commit (toward
-- HEAD) and re-open the diff in place. q closes the review — and quits this
-- nvim when it was launched solely for the review (g:review_commit set).
local function review_open(sha)
    vim.g.review_commit = sha
    pcall(vim.cmd, "DiffviewClose") -- close current view first (no quit) to avoid stacking tabs
    vim.schedule(function() vim.cmd("DiffviewOpen " .. sha .. "^.." .. sha) end)
end

local function review_nav(dir)
    local cur = vim.g.review_commit
    if not cur or cur == "" then
        vim.notify("No commit under review", vim.log.levels.WARN)
        return
    end
    local cmd = dir == "prev"
        and { "git", "rev-parse", "--verify", "--quiet", cur .. "~1" }
        or { "git", "rev-list", "--reverse", "--ancestry-path", cur .. "..HEAD" }
    local target = (vim.fn.systemlist(cmd) or {})[1]
    if target and target:match("^%x%x%x+$") then
        review_open(target)
    else
        vim.notify(("No %s commit"):format(dir == "prev" and "older" or "newer"), vim.log.levels.INFO)
    end
end

local function review_close()
    if vim.g.review_commit then
        vim.cmd("qa") -- launched for review → quit nvim (Zed clears the tab)
    else
        pcall(vim.cmd, "DiffviewClose") -- interactive nvim → just close the diff
    end
end

require("lazy").setup({
    { "projekt0n/github-nvim-theme", name = "github-theme", priority = 1000 },
    { "mustache/vim-mustache-handlebars", ft = { "handlebars", "html.handlebars", "mustache", "html.mustache" } },

    { "nvim-lualine/lualine.nvim", opts = {
        options = { theme = "auto", component_separators = "|", section_separators = "" },
        sections = { lualine_c = { { "filename", path = 1 } } },
    } },

    { "nvim-tree/nvim-web-devicons", lazy = true },
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh", "DiffviewFileHistory" },
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = {
            hooks = {
                -- On open, focus the additions (right-most) diff window so j/k
                -- scroll both panes together (they're scrollbind-linked in diff mode).
                view_opened = function()
                    vim.schedule(function()
                        -- diffview sets dull diff colors on open; restyle them
                        -- (vivid bg, no fg) so treesitter shows on changed lines.
                        style_diff_hl()
                        local target, best = nil, -1
                        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                            if vim.wo[w].diff then
                                place_diff_signs(w)
                                local col = vim.api.nvim_win_get_position(w)[2]
                                if col > best then best, target = col, w end
                            end
                        end
                        if target then vim.api.nvim_set_current_win(target) end
                    end)
                end,
            },
            keymaps = {
                -- q closes the review; ]C/[C step to the next/previous commit;
                -- L shows the commit message — in both the diff and the panel.
                view = {
                    { "n", "q", review_close, { desc = "Close review" } },
                    { "n", "]C", function() review_nav("next") end, { desc = "Next (newer) commit" } },
                    { "n", "[C", function() review_nav("prev") end, { desc = "Prev (older) commit" } },
                    { "n", "L", function() require("diffview.actions").open_commit_log() end, { desc = "Open the commit log" } },
                },
                file_panel = {
                    { "n", "q", review_close, { desc = "Close review" } },
                    { "n", "]C", function() review_nav("next") end, { desc = "Next (newer) commit" } },
                    { "n", "[C", function() review_nav("prev") end, { desc = "Prev (older) commit" } },
                },
            },
        },
    },

    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        lazy = false,
        build = ":TSUpdate",
        config = function()
            -- Parsers compile via tree-sitter-cli (first launch installs them).
            require("nvim-treesitter").install({
                "bash", "c", "css", "diff", "dockerfile", "gitcommit", "go",
                "html", "javascript", "json", "lua", "markdown",
                "markdown_inline", "python", "rust", "toml", "tsx",
                "typescript", "vim", "vimdoc", "yaml",
            })
            -- Enable treesitter highlighting for any buffer with a parser —
            -- including diffview's diff buffers, so changed lines keep syntax.
            -- pcall falls back to regex :syntax for langs without a parser.
            vim.api.nvim_create_autocmd("FileType", {
                callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
            })
        end,
    },
}, {
    checker = { enabled = false },
    change_detection = { notify = false },
})

require("github-theme").setup({
    options = { transparent = true, styles = { comments = "italic" } },
})
vim.cmd.colorscheme("github_dark")

-- Re-apply diff colors after any colorscheme change (see style_diff_hl above).
vim.api.nvim_create_autocmd("ColorScheme", { callback = style_diff_hl })
style_diff_hl()

-- Re-draw the gutter change-bars when diffview swaps in a new diff buffer
-- (e.g. switching files with <tab>), not just on the initial view_opened.
vim.api.nvim_create_autocmd("User", {
    pattern = "DiffviewDiffBufWinEnter",
    callback = function()
        vim.schedule(function()
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.wo[w].diff then place_diff_signs(w) end
            end
        end)
    end,
})
