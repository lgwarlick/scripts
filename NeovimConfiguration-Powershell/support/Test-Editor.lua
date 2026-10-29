-- Functional checks run only by the validation harness in a disposable directory.
local function contains(items, label)
    for _, item in ipairs(items) do
        if item.label == label then return true end
    end
    return false
end

return function()
    local project = vim.fn.getcwd()
    -- Stop Git discovery before it reaches the repository containing these fixtures.
    vim.env.GIT_CEILING_DIRECTORIES = vim.fs.dirname(project)
    assert(not vim.g.bootstrap_project_executed, "Project-local .lazy.lua executed")
    vim.cmd("Neotree focus")
    assert(vim.wait(3000, function() return vim.bo.filetype == "neo-tree" end), "File tree did not open")
    -- Complete the asynchronous initial filesystem scan before closing its window.
    vim.wait(200, function() return false end)
    vim.cmd("Neotree close")
    local editing_buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(editing_buffer)

    local message
    local notify = vim.notify
    vim.notify = function(text, level, options)
        message = text
        return notify(text, level, options)
    end
    vim.cmd.normal(" f")
    vim.notify = notify
    assert(message and message:find("No formatter configured", 1, true), "Missing no-formatter message")
    vim.cmd.normal(" d")

    local keys = vim.api.nvim_replace_termcodes("i(<Esc>", true, false, true)
    vim.api.nvim_feedkeys(keys, "xt", false)
    assert(vim.api.nvim_get_current_line() == "()", "Autopairs did not insert a pair")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "bootstrapCompletionWord", "other" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local buffer_result
    require("blink.cmp.sources.buffer").new({}):get_completions({}, function(result) buffer_result = result end)
    assert(vim.wait(3000, function() return buffer_result ~= nil end), "Buffer completion timed out")
    assert(contains(buffer_result.items, "bootstrapCompletionWord"), "Buffer completion missing a word")

    vim.fn.writefile({ "fixture" }, project .. "/completion-fixture.txt")
    local path_result
    local context = { bufnr = vim.api.nvim_get_current_buf(), line = "./", cursor = { 1, 2 }, bounds = { start_col = 3, length = 0 } }
    require("blink.cmp.sources.path").new({ get_cwd = function() return project end }):get_completions(context, function(result) path_result = result end)
    assert(vim.wait(3000, function() return path_result ~= nil end), "Path completion timed out")
    assert(contains(path_result.items, "completion-fixture.txt"), "Path completion missing a file")

    vim.api.nvim_set_current_buf(editing_buffer)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.snippet.expand("hello ${1:world}$0")
    assert(vim.api.nvim_get_current_line() == "hello world", "Snippet expansion failed")
    vim.snippet.stop()
    vim.cmd("stopinsert")

    -- Real local Git fixture; no remote or user identity configuration is needed.
    local git = vim.fn.exepath("git")
    local function run(arguments)
        local command = { git, "-C", project }
        vim.list_extend(command, arguments)
        local result = vim.system(command, { text = true }):wait(5000)
        assert(result.code == 0, result.stderr)
    end
    run({ "init" })
    vim.fn.writefile({ "original" }, project .. "/tracked.txt")
    run({ "add", "tracked.txt" })
    run({ "-c", "user.name=Bootstrap Test", "-c", "user.email=bootstrap@example.invalid", "-c", "core.hooksPath=NUL", "-c", "commit.gpgSign=false", "commit", "-m", "fixture" })
    vim.cmd("edit! " .. vim.fn.fnameescape(project .. "/tracked.txt"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
    assert(vim.wait(5000, function()
        local status = vim.b.gitsigns_status_dict
        return status and status.changed == 1
    end), "Gitsigns did not report the changed tracked line")
    vim.cmd("enew!")
    local outside = project .. "-outside"
    vim.fn.mkdir(outside, "p")
    local discovery = vim.system({ git, "-C", outside, "rev-parse", "--show-toplevel" }, { text = true }):wait(5000)
    assert(discovery.code ~= 0, "Outside-repository fixture unexpectedly has a Git root")
    vim.cmd("edit! " .. vim.fn.fnameescape(outside .. "/outside.txt"))
    vim.wait(200, function() return false end)
    assert(not vim.b.gitsigns_status_dict, "Buffer outside a repository unexpectedly attached")
    assert(not vim.g.bootstrap_project_executed, "Project-local .lazy.lua executed")
end
