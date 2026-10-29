-- Explicit user action; no installation or registry refresh during editor startup.
return function(config)
    local tools = vim.json.decode(table.concat(vim.fn.readfile(config .. "/tools.json"), "\n"))
    for _, prerequisite in ipairs(tools.prerequisites) do
        local executable = prerequisite.command
        assert(vim.fn.executable(executable) == 1, "Install prerequisite on PATH: " .. executable)
        local command = { executable }
        vim.list_extend(command, prerequisite.args)
        local result = vim.system(command, { text = true }):wait(15000)
        local version = (result.stdout or ""):match("(%d+%.%d+%.%d+)")
        assert(result.code == 0 and version == prerequisite.Version,
            executable .. " requires reviewed version " .. prerequisite.Version .. "; found " .. tostring(version))
    end
    assert(vim.fn.executable("npm") == 1, "npm must accompany Node.js on PATH")
    local registry = require("mason-registry")
    local refreshed, success = false, false
    registry.refresh(function(ok) success, refreshed = ok, true end)
    assert(vim.wait(120000, function() return refreshed end, 100), "Registry refresh timed out")
    assert(success, "Pinned Mason registry refresh failed")
    for _, name in ipairs(vim.fn.sort(vim.tbl_keys(tools.packages))) do
        local package = registry.get_package(name)
        if package:get_installed_version() ~= tools.packages[name] then
            local complete, installed = false, false
            package:install({ version = tools.packages[name] }, function(ok)
                installed, complete = ok, true
            end)
            assert(vim.wait(600000, function() return complete end, 100), "Install timed out: " .. name)
            assert(installed, "Install failed: " .. name .. "; inspect :MasonLog")
        end
    end
    local old_cc = vim.env.CC
    vim.env.CC = vim.fn.exepath("clang")
    local ok, error_message = pcall(function()
        require("nvim-treesitter").install(tools.parsers):wait(600000)
    end)
    vim.env.CC = old_cc
    assert(ok, error_message)
    for _, parser in ipairs(tools.parsers) do
        local loaded, error_message = vim.treesitter.language.add(parser)
        assert(loaded, "Parser install failed: " .. parser .. ": " .. tostring(error_message))
    end
    vim.notify("Pinned language tools installed. Restart Neovim to enable servers.")
end
