-- Run from an isolated fixture directory after provisioning. No installs are made.
return function()
    local root = vim.fn.getcwd()
    vim.fn.writefile({ '["ci/custom.yml", "ci/templates/**/*.yml"]' }, root .. "/.nvim-azure-pipelines.json")
    vim.fn.mkdir(root .. "/ci/templates", "p")
    vim.fn.writefile({ "parameters: []", "steps:", "- script: echo hello" }, root .. "/ci/templates/build.yml")
    local cases = {
        { "general.yml", "yamlls", "yaml", { "key: [one, two]" } },
        { "azure-pipelines.yml", "azure_pipelines_ls", "yaml", { "steps:", "- template: ci/templates/build.yml" } },
        { "ci/templates/build.yml", "azure_pipelines_ls", "yaml" },
        { "ci/custom.yml", "azure_pipelines_ls", "yaml", { "steps:", "- template: templates/build.yml" } },
        { "main.tf", "terraformls", "terraform", { 'variable "name" {', 'type=string', '}' } },
        { "main.ps1", "powershell_es", "powershell", { '$value=1', 'Write-Output $value' } },
        { "main.sh", "bashls", "bash", { '#!/usr/bin/env bash', 'echo "$HOME"' } },
        { "package.json", "jsonls", "json", { '{"name":"fixture","version":"1.0.0"}' } },
        { "tsconfig.json", "jsonls", "json", { '// comment', '{"compilerOptions":{"strict":true}}' } },
    }
    for _, case in ipairs(cases) do
        local file, server, parser, lines = unpack(case)
        if lines then vim.fn.writefile(lines, root .. "/" .. file) end
        vim.cmd("edit! " .. vim.fn.fnameescape(root .. "/" .. file))
        local buf = vim.api.nvim_get_current_buf()
        assert(vim.wait(90000, function() return #vim.lsp.get_clients({ bufnr = buf, name = server }) == 1 end, 100),
            "Server attachment timed out: " .. file)
        if parser == "yaml" then
            assert(#vim.lsp.get_clients({ bufnr = buf }) == 1, "Overlapping YAML servers: " .. file)
        end
        local tree = vim.treesitter.get_parser(buf, parser):parse()[1]
        assert(tree and not tree:root():has_error(), "Parser failed on valid fixture: " .. file)
        assert(vim.treesitter.highlighter.active[buf], "Highlighting missing: " .. file)
        local client = vim.lsp.get_clients({ bufnr = buf, name = server })[1]
        local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
        local response = client:request_sync("textDocument/completion", params, 30000, buf)
        assert(response and not response.err, "Completion request failed: " .. file)
        local finished, format_error = false, nil
        require("conform").format({ bufnr = buf, async = false, timeout_ms = 30000,
            lsp_format = server == "powershell_es" and "fallback" or "never" }, function(err)
            format_error, finished = err, true
        end)
        assert(finished and not format_error, "Formatting failed: " .. file .. ": " .. tostring(format_error))
        if file == "azure-pipelines.yml" then
            params.position = { line = 1, character = 20 }
            local definition = client:request_sync("textDocument/definition", params, 30000, buf)
            assert(definition and definition.result and not vim.tbl_isempty(definition.result), "Local template navigation failed")
        end
        -- Introduce a syntax error and require an actual server diagnostic.
        local invalid = ({ yaml = "key: [", terraform = 'variable "broken" {', powershell = "function {", bash = "if then", json = '{"broken": ]' })[parser]
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { invalid })
        assert(vim.wait(30000, function()
            return #vim.diagnostic.get(buf, { namespace = vim.lsp.diagnostic.get_namespace(client.id) }) > 0
        end, 100), "Missing diagnostics: " .. file)
        io.stdout:write("PASS language " .. file .. "\n")
    end
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'name = "fixture"' })
    vim.bo.filetype = "hcl"
    assert(not vim.treesitter.get_parser(0, "hcl"):parse()[1]:root():has_error(), "HCL parser failed")
end
