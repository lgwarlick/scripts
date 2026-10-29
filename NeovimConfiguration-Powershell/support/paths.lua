-- Invoked with -u NONE, -i NONE, --noplugin and no user environment initialization.
local paths = {}
for _, name in ipairs({ "config", "data", "cache", "state" }) do
    paths[name] = vim.fn.stdpath(name)
end
io.stdout:write("BOOTSTRAP_PATHS=" .. vim.json.encode(paths) .. "\n")
