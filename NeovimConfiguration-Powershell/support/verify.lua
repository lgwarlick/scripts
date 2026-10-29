-- Capture setup errors before init.lua and wait for scheduled work after VimEnter.
local errors = {}
local original_notify = vim.notify
vim.notify = function(message, level, options)
    if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(message) end
    return original_notify(message, level, options)
end
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        vim.defer_fn(function()
            local ok, err = xpcall(function()
                assert(vim.v.errmsg == "", vim.v.errmsg)
                assert(#errors == 0, table.concat(errors, "\n"))
                local config = require("lazy.core.config")
                assert(not config.options.local_spec, "Project specifications enabled")
                assert(not config.options.install.missing, "Implicit installation enabled")
                local count = 0
                for name, plugin in pairs(config.plugins) do
                    if name ~= "lazy.nvim" then
                        count = count + 1
                        assert(plugin._.loaded, "Plugin did not load: " .. name)
                        assert(not plugin._.has_errors, "Plugin setup failed: " .. name)
                    end
                end
                assert(count == 12, "Unexpected plugin inventory: " .. count)
                for _, module in ipairs({ "mason", "mason-lspconfig", "conform", "nvim-treesitter",
                    "blink.cmp", "neo-tree", "gitsigns", "nvim-autopairs", "lint" }) do
                    assert(package.loaded[module], "Module did not initialize: " .. module)
                end
                assert(next(require("lint").linters_by_ft) == nil, "Unexpected linters")
                assert(#require("mason.settings").current.registries == 0, "Unexpected Mason registry")
                assert(#require("mason.settings").current.system_registries == 0, "Unexpected Mason system registry")
                assert(require("mason-lspconfig.settings").current.automatic_enable == false, "Automatic LSP enabling")
                assert(vim.fn.maparg("<Space>e", "n") ~= "", "Missing tree mapping")
                assert(vim.fn.maparg("<Space>f", "n") ~= "", "Missing formatter mapping")
                assert(require("blink.cmp").get_lsp_capabilities().textDocument.completion, "Missing LSP capabilities")
                if vim.env.NVIM_BOOTSTRAP_EDITOR_TEST then
                    dofile(vim.env.NVIM_BOOTSTRAP_EDITOR_TEST)()
                end
                assert(vim.v.errmsg == "", vim.v.errmsg)
                assert(#errors == 0, table.concat(errors, "\n"))
                io.stdout:write("BOOTSTRAP_VERIFIED\n")
            end, debug.traceback)
            if not ok then
                io.stderr:write(tostring(err) .. "\n")
                vim.cmd("cquit 1")
            else
                vim.cmd("qa!")
            end
        end, 250)
    end,
})
