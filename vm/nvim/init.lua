-- =============================================================================
-- init.lua — slim VM-side Neovim config.
-- Git-grep-driven. No LSP / no treesitter / no fuzzy fancy. Boots in <500ms.
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

-- :grep / :Ggrep go through git grep (project-scoped, .gitignore-aware).
opt.grepprg = "git --no-pager grep --no-color -n --column"
opt.grepformat = "%f:%l:%c:%m"

-- Built-in :find descends arbitrarily under cwd (replacement for telescope's find_files).
opt.path:append("**")

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

-- :Ggrep populates the quickfix. ]q / [q walks results.
map("n", "]q", "<cmd>cnext<CR>zz", { desc = "Next quickfix" })
map("n", "[q", "<cmd>cprev<CR>zz", { desc = "Prev quickfix" })

map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprev<CR>", { desc = "Prev buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

map("n", "<leader>T", "<cmd>tab term<CR>", { desc = "Terminal in new tab" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Search-and-navigation — git grep based.
map("n", "<leader>fs", ":Ggrep ", { desc = "Git grep" })
map("n", "<leader>fS", function()
    local word = vim.fn.expand("<cword>")
    if word == "" then return end
    vim.cmd(("Ggrep -i -w %s"):format(vim.fn.shellescape(word)))
end, { desc = "Git grep <cword>" })
map("n", "<leader>ff", ":find ", { desc = "Find file" })

vim.filetype.add({ extension = { hbs = "handlebars" } })

-- =============================================================================
-- Plugin manager: lazy.nvim (auto-installs on first launch)
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

require("lazy").setup({
    { "projekt0n/github-nvim-theme", name = "github-theme", priority = 1000 },
    { "mustache/vim-mustache-handlebars", ft = "handlebars" },

    -- Filesystem-as-buffer.
    {
        "stevearc/oil.nvim",
        config = function()
            require("oil").setup({
                view_options = { show_hidden = true },
                keymaps = { ["q"] = "actions.close" },
            })
            map("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
        end,
    },

    -- Git: gutter signs + hunk actions + Ggrep.
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns").setup({
                current_line_blame = true,
                current_line_blame_opts = { delay = 500 },
                on_attach = function(bufnr)
                    if vim.bo[bufnr].buftype ~= "" then return false end
                    local gs = package.loaded.gitsigns
                    local function bmap(mode, lhs, rhs, desc)
                        map(mode, lhs, rhs, { buffer = bufnr, desc = desc })
                    end
                    bmap("n", "]h", function() gs.nav_hunk("next") end, "Next hunk")
                    bmap("n", "[h", function() gs.nav_hunk("prev") end, "Prev hunk")
                    bmap("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
                    bmap("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
                    bmap("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
                    bmap("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
                    bmap("n", "<leader>hd", gs.diffthis, "Diff against index")
                end,
            })
        end,
    },

    -- Fugitive supplies :Git, :Ggrep, :Glog. :Ggrep is the search primitive.
    {
        "tpope/vim-fugitive",
        cmd = { "Git", "Ggrep", "Gdiffsplit", "Gvdiffsplit", "Gclog" },
        keys = {
            { "<leader>gg", "<cmd>Git<CR>", desc = "Git status" },
            { "<leader>gd", "<cmd>tab Git diff<CR>", desc = "Git diff (uncommitted)" },
            { "<leader>gl", "<cmd>tab Git log --oneline --decorate -30<CR>", desc = "Git log (30)" },
        },
    },

    { "nvim-lualine/lualine.nvim", opts = {
        options = { theme = "auto", component_separators = "|", section_separators = "" },
        sections = { lualine_b = { "branch", "diff" }, lualine_c = { { "filename", path = 1 } } },
    } },

    { "kylechui/nvim-surround", event = "VeryLazy", config = true },
    { "windwp/nvim-autopairs", event = "InsertEnter", config = true },

    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        config = function()
            local wk = require("which-key")
            wk.setup({ delay = 200 })
            wk.add({
                { "<leader>f", group = "Find" },
                { "<leader>g", group = "Git" },
                { "<leader>h", group = "Hunks" },
                { "<leader>b", group = "Buffer" },
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
