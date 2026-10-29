-- Offline contract checks run with the existing isolated editor test harness.
return function(config)
    local languages = dofile(config .. "/languages.lua")
    local root = vim.fn.getcwd()
    local function selected(path, azure)
        local buffer = vim.fn.bufadd(root .. "/" .. path)
        local clients = {}
        for _, name in ipairs({ "yamlls", "azure_pipelines_ls" }) do
            vim.lsp.config[name].root_dir(buffer, function() clients[#clients + 1] = name end)
        end
        assert(#clients == 1 and clients[1] == (azure and "azure_pipelines_ls" or "yamlls"), path)
    end
    vim.fn.mkdir(root .. "/azure-pipelines/templates", "p")
    vim.fn.writefile({ "steps: []" }, root .. "/azure-pipelines.yml")
    vim.fn.writefile({ 'normal: true' }, root .. "/general.yml")
    vim.fn.writefile({ '["ci/custom.yml", "ci/templates/**/*.yaml"]' }, root .. "/.nvim-azure-pipelines.json")
    selected("general.yml", false)
    selected("azure-pipelines.yml", true)
    selected("azure-pipelines/templates/build.yml", true)
    selected("ci/custom.yml", true)
    selected("ci/templates/build.yaml", true)
    selected("ci/ordinary.yml", false)
    local client = { root_dir = root }
    vim.lsp.config.azure_pipelines_ls.before_init({}, client)
    assert(next(client.settings.yaml.schemas), "Missing Azure schema associations")
    assert(vim.lsp.config.yamlls.settings.yaml.schemaStore.enable == false)
    for _, name in ipairs({ "yamlls", "azure_pipelines_ls", "terraformls", "powershell_es", "bashls", "jsonls" }) do
        assert(vim.lsp.config[name].capabilities.textDocument.completion, "Missing completion: " .. name)
    end
    assert(vim.lsp.config.bashls.settings.bashIde.shfmt.path == "", "Duplicate Bash formatting")
    assert(require("lint").linters_by_ft.sh == nil, "Duplicate ShellCheck diagnostics")
    -- Exercise the real shortcut with a formatter spy, including its PowerShell fallback.
    local conform = require("conform")
    local original = conform.format
    local formatting
    conform.format = function(options) formatting = options end
    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buffer)
    vim.bo.filetype = "ps1"
    vim.cmd.normal(" f")
    conform.format = original
    assert(formatting and formatting.lsp_format == "fallback", "PowerShell formatter unavailable")
    assert(languages.is_azure(root .. "/azure-pipelines.yml", root))
end
