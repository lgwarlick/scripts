return {
    { "nvim-lua/plenary.nvim" },
    { "MunifTanjim/nui.nvim" },
    { "neovim/nvim-lspconfig" },
    { "b0o/SchemaStore.nvim" },
    {
        "mason-org/mason.nvim",
        opts = function()
            local config = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
            local tools = vim.json.decode(table.concat(vim.fn.readfile(config .. "/tools.json"), "\n"))
            return { install_root_dir = vim.g.neovim_bootstrap.plugin_root .. "/tools",
                registries = { tools.registry }, system_registries = {} }
        end,
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = { "mason.nvim", "nvim-lspconfig", "blink.cmp", "SchemaStore.nvim" },
        config = function()
            -- setup() refreshes the registry: run it only during explicit provisioning.
            require("mason-lspconfig.settings").set({ ensure_installed = {}, automatic_enable = false })
            local config = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
            dofile(config .. "/languages.lua").setup(config)
        end,
    },
    { "stevearc/conform.nvim", opts = { formatters_by_ft = {
        yaml = { "prettier" }, json = { "prettier" }, jsonc = { "prettier" },
        terraform = { "terraform_fmt" }, ["terraform-vars"] = { "terraform_fmt" },
        sh = { "shfmt" }, bash = { "shfmt" },
    } } },
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        -- Keep compiled parsers with this baseline so backups retain their dependencies.
        opts = function() return { install_dir = vim.g.neovim_bootstrap.plugin_root .. "/parsers" } end,
    },
    {
        "saghen/blink.cmp",
        opts = {
            keymap = { preset = "default" },
            fuzzy = { implementation = "lua" },
            sources = { default = { "lsp", "path", "snippets", "buffer" } },
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
    {
        "mfussenegger/nvim-lint",
        config = function()
            require("lint").linters_by_ft = { terraform = { "tflint" }, ["terraform-vars"] = { "tflint" } }
            vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
                group = vim.api.nvim_create_augroup("BootstrapLint", { clear = true }),
                callback = function()
                    if vim.fn.executable("tflint") == 1 then require("lint").try_lint() end
                end,
            })
        end,
    },
}
