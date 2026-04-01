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

-- Diagnostic navigation
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Prev diagnostic" })

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

-- =============================================================================
-- Plugins
-- =============================================================================
require("lazy").setup({

    -- =========================================================================
    -- Theme
    -- =========================================================================
    { "catppuccin/nvim", name = "catppuccin", priority = 1000 },

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
        },
        config = function()
            local telescope = require("telescope")
            local actions = require("telescope.actions")

            telescope.setup({
                defaults = {
                    preview = {
                        treesitter = false,
                    },
                    layout_strategy = "horizontal",
                    layout_config = { prompt_position = "top" },
                    sorting_strategy = "ascending",
                    mappings = {
                        i = {
                            ["<C-j>"] = actions.move_selection_next,
                            ["<C-k>"] = actions.move_selection_previous,
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                        },
                    },
                },
                pickers = {
                    find_files = { hidden = true },
                    live_grep = {
                        additional_args = function() return { "--hidden" } end,
                    },
                },
            })
            telescope.load_extension("fzf")

            local builtin = require("telescope.builtin")
            map("n", "<C-p>", builtin.find_files, { desc = "Find files" })
            map("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
            map("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
            map("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
            map("n", "<leader>fh", builtin.help_tags, { desc = "Help" })
            map("n", "<leader>fs", builtin.grep_string, { desc = "Grep word under cursor" })
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
            map("n", "<leader>e", "<cmd>Oil<CR>", { desc = "File explorer" })
            map("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
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
                    local gs = package.loaded.gitsigns
                    local function bmap(mode, lhs, rhs, desc)
                        map(mode, lhs, rhs, { buffer = bufnr, desc = desc })
                    end

                    -- Hunk navigation
                    bmap("n", "]h", gs.next_hunk, "Next hunk")
                    bmap("n", "[h", gs.prev_hunk, "Prev hunk")

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
        cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Glog", "Gblame" },
        keys = {
            { "<leader>gg", "<cmd>Git<CR>", desc = "Git status (fugitive)" },
            { "<leader>gd", "<cmd>Gvdiffsplit<CR>", desc = "Git diff split" },
            { "<leader>gl", "<cmd>Git log --oneline -30<CR>", desc = "Git log" },
            { "<leader>gL", "<cmd>Git log --oneline --all --graph -30<CR>", desc = "Git log graph" },
        },
    },

    -- =========================================================================
    -- Treesitter (Neovim 0.12+ API)
    -- =========================================================================
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter").install({
                "python", "javascript", "typescript", "html", "css",
                "json", "yaml", "toml", "bash", "lua", "markdown",
                "markdown_inline", "git_rebase", "gitcommit", "diff",
            })

            -- Enable treesitter highlighting for all filetypes with a parser
            vim.api.nvim_create_autocmd("FileType", {
                callback = function()
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
        "williamboman/mason.nvim",
        dependencies = { "williamboman/mason-lspconfig.nvim" },
        config = function()
            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = { "pyright", "ts_ls" },
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
        opts = {},
    },

    -- =========================================================================
    -- Snacks: bigfile + word highlighting
    -- =========================================================================
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            bigfile = { enabled = true },
            words = { enabled = true },
        },
        keys = {
            { "]]", function() Snacks.words.jump(1, true) end, desc = "Next LSP reference" },
            { "[[", function() Snacks.words.jump(-1, true) end, desc = "Prev LSP reference" },
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
            wk.setup({ delay = 500 })
            wk.add({
                { "<leader>f", group = "Find" },
                { "<leader>g", group = "Git" },
                { "<leader>h", group = "Hunks" },
                { "<leader>b", group = "Buffer" },
                { "<leader>x", group = "Diagnostics" },
            })
        end,
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
vim.lsp.config("pyright", {})
vim.lsp.config("ts_ls", {})
vim.lsp.enable({ "pyright", "ts_ls" })

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local bufnr = args.buf
        local function lmap(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
        end
        lmap("gd", vim.lsp.buf.definition, "Go to definition")
        lmap("gr", vim.lsp.buf.references, "References")
        lmap("gI", vim.lsp.buf.implementation, "Implementation")
        lmap("K", vim.lsp.buf.hover, "Hover docs")
        lmap("<leader>rn", vim.lsp.buf.rename, "Rename")
        lmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
        lmap("gD", vim.lsp.buf.declaration, "Go to declaration")
        lmap("<leader>D", vim.lsp.buf.type_definition, "Type definition")
    end,
})

-- Open difftool for commit under cursor in git log
vim.api.nvim_create_autocmd("FileType", {
    pattern = "git",
    callback = function()
        vim.keymap.set("n", "<CR>", function()
            local word = vim.fn.expand("<cword>")
            -- Check if it looks like a commit hash
            if word:match("^%x%x%x%x%x%x+$") then
                vim.cmd("tabnew")
                vim.fn.termopen("git difftool " .. word .. "~.." .. word)
                vim.cmd("startinsert")
            end
        end, { buffer = true, desc = "Open commit in difftool" })
    end,
})

require("catppuccin").setup({
    flavour = "mocha",
    transparent_background = true,
    float = {
        transparent = false,
        solid = false,
    },
})

vim.cmd.colorscheme "catppuccin"
