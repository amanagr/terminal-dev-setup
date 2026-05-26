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

-- Diff highlight groups (set by the theme and/or diffview) carry a foreground
-- that overrides treesitter syntax on changed lines, leaving them a flat
-- green/red. Strip the fg but keep the bg, so syntax colors show through on
-- added/changed/deleted lines while the diff background still marks them.
local function strip_diff_fg()
    for _, g in ipairs({ "DiffAdd", "DiffChange", "DiffText", "DiffDelete" }) do
        local h = vim.api.nvim_get_hl(0, { name = g, link = false })
        h.fg = nil
        vim.api.nvim_set_hl(0, g, h)
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
                        -- diffview sets diff colors on open; re-strip their fg
                        -- so treesitter shows on changed lines.
                        strip_diff_fg()
                        local target, best = nil, -1
                        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                            if vim.wo[w].diff then
                                local col = vim.api.nvim_win_get_position(w)[2]
                                if col > best then best, target = col, w end
                            end
                        end
                        if target then vim.api.nvim_set_current_win(target) end
                    end)
                end,
            },
            keymaps = {
                -- L opens the commit-message popup from the diff panes too,
                -- not just the file-tree panel.
                view = {
                    { "n", "L", function() require("diffview.actions").open_commit_log() end, { desc = "Open the commit log" } },
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

-- Re-strip diff fg after any colorscheme change (see strip_diff_fg above).
vim.api.nvim_create_autocmd("ColorScheme", { callback = strip_diff_fg })
strip_diff_fg()
