local M = {}
local azure_schema = "https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/master/service-schema.json"
local defaults = { "**/azure-pipelines.yml", "**/azure-pipelines.yaml",
    "**/azure-pipelines/**/*.yml", "**/azure-pipelines/**/*.yaml" }

function M.patterns(root)
    local patterns = vim.deepcopy(defaults)
    -- Data only: never execute project Lua. Rules are relative to the project root.
    local file = root .. "/.nvim-azure-pipelines.json"
    if vim.fn.filereadable(file) == 1 then
        local ok, extra = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), "\n"))
        if ok and type(extra) == "table" then
            for _, pattern in ipairs(extra) do
                if type(pattern) == "string" then
                    local absolute = root:gsub("\\", "/") .. "/" .. pattern
                    if pcall(vim.glob.to_lpeg, absolute) then patterns[#patterns + 1] = absolute end
                end
            end
        end
    end
    return patterns
end

function M.root(buf)
    return vim.fs.root(buf, { ".nvim-azure-pipelines.json", ".git", "azure-pipelines.yml", "azure-pipelines.yaml" })
        or vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
end

function M.is_azure(path, root)
    path = path:gsub("\\", "/")
    for _, pattern in ipairs(M.patterns(root)) do
        if vim.glob.to_lpeg(pattern):match(path) then return true end
    end
    return false
end

function M.setup(config)
    require("mason-lspconfig")
    local capabilities = require("blink.cmp").get_lsp_capabilities()
    local mason = vim.g.neovim_bootstrap.plugin_root .. "/tools"
    local servers = { "yamlls", "azure_pipelines_ls", "terraformls", "powershell_es", "bashls", "jsonls" }
    for _, server in ipairs(servers) do vim.lsp.config(server, { capabilities = capabilities }) end
    local schemas = require("schemastore")
    vim.lsp.config("yamlls", {
        root_dir = function(buf, on_dir)
            local root = M.root(buf)
            if not M.is_azure(vim.api.nvim_buf_get_name(buf), root) then on_dir(root) end
        end,
        settings = { yaml = { schemaStore = { enable = false, url = "" },
            schemas = schemas.yaml.schemas(), validate = true, completion = true, format = { enable = false } } },
    })
    vim.lsp.config("azure_pipelines_ls", {
        root_dir = function(buf, on_dir)
            local root = M.root(buf)
            if M.is_azure(vim.api.nvim_buf_get_name(buf), root) then on_dir(root) end
        end,
        before_init = function(_, client_config)
            client_config.settings = { yaml = { schemaStore = { enable = false, url = "" },
                schemas = { [azure_schema] = M.patterns(client_config.root_dir) },
                validate = true, completion = true, format = { enable = false } } }
        end,
    })
    vim.lsp.config("jsonls", { settings = { json = { schemas = schemas.json.schemas(),
        validate = { enable = true }, format = { enable = false } } } })
    vim.lsp.config("powershell_es", { shell = "pwsh.exe",
        bundle_path = mason .. "/packages/powershell-editor-services",
        settings = { powershell = { scriptAnalysis = { enable = true } } } })
    vim.lsp.config("bashls", { settings = { bashIde = {
        shellcheckPath = "shellcheck", shfmt = { path = "" },
    } } })
    -- Missing tools are allowed during deployment verification. Provisioning is explicit.
    local commands = { yamlls = "yaml-language-server", azure_pipelines_ls = "azure-pipelines-language-server",
        terraformls = "terraform-ls", powershell_es = "pwsh.exe", bashls = "bash-language-server", jsonls = "vscode-json-language-server" }
    for _, server in ipairs(servers) do
        local command = vim.fn.exepath(commands[server]):gsub("\\", "/"):lower()
        local managed = vim.startswith(command, (mason .. "/bin/"):lower())
        if (server == "powershell_es" and command ~= ""
            and vim.fn.isdirectory(mason .. "/packages/powershell-editor-services") == 1) or managed then
            vim.lsp.enable(server)
        end
    end
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("BootstrapTreesitter", { clear = true }),
        pattern = { "yaml", "terraform", "terraform-vars", "hcl", "ps1", "sh", "bash", "json", "jsonc" },
        callback = function(event)
            local language = ({ ps1 = "powershell", sh = "bash", jsonc = "json", ["terraform-vars"] = "terraform" })[vim.bo[event.buf].filetype]
                or vim.bo[event.buf].filetype
            -- Parsers are installed only by BootstrapInstallTools, never on buffer open.
            local ok, loaded = pcall(vim.treesitter.language.add, language)
            if ok and loaded then vim.treesitter.start(event.buf, language) end
        end,
    })
    vim.api.nvim_create_user_command("BootstrapInstallTools", function()
        dofile(config .. "/provision.lua")(config)
    end, { desc = "Download pinned Mason tools and Treesitter parsers; restart Neovim afterwards" })
end

return M
