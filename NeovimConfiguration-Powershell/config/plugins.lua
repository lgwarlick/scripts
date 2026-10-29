return {
    { "nvim-lua/plenary.nvim" },
    { "MunifTanjim/nui.nvim" },
    { "neovim/nvim-lspconfig" },
    -- Empty registries avoid mason-lspconfig's implicit network refresh in Phase 1.
    { "mason-org/mason.nvim", opts = { registries = {}, system_registries = {} } },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = { "mason.nvim", "nvim-lspconfig" },
        opts = { ensure_installed = {}, automatic_enable = false },
    },
    { "stevearc/conform.nvim", opts = { formatters_by_ft = {} } },
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        -- Explicitly add the standard parser location after Lazy resets runtimepath.
        opts = function() return { install_dir = vim.fn.stdpath("data") .. "/site" } end,
    },
    {
        "saghen/blink.cmp",
        opts = {
            keymap = { preset = "default" },
            fuzzy = { implementation = "lua" },
            sources = { default = { "path", "snippets", "buffer" } },
            completion = { menu = { draw = { columns = { { "label", "label_description", gap = 1 }, { "kind" } } } } },
        },
    },
    {
        "nvim-neo-tree/neo-tree.nvim",
        branch = "v3.x",
        dependencies = { "plenary.nvim", "nui.nvim" },
        opts = {
            default_component_configs = {
                icon = { folder_closed = "+", folder_open = "-", folder_empty = "-", default = "*" },
                indent = { expander_collapsed = "+", expander_expanded = "-" },
                git_status = { symbols = { added = "+", modified = "~", deleted = "-", renamed = "R",
                    untracked = "?", ignored = "!", unstaged = "U", staged = "S", conflict = "C" } },
                diagnostics = { symbols = { hint = "H", info = "I", warn = "W", error = "E" } },
            },
        },
    },
    { "lewis6991/gitsigns.nvim", opts = {} },
    { "windwp/nvim-autopairs", opts = {} },
    { "mfussenegger/nvim-lint", config = function() require("lint").linters_by_ft = {} end },
}
