local noop = function(...) end

if not _G.__is_log then
  return { debug = noop, info = noop, error = noop }
end

local log_file = vim.fn.stdpath("log") .. "/kube.nvim.log"

---@param level string
local function logger(level)
  return function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local arg = select(i, ...)
      table.insert(parts, type(arg) == "string" and arg or vim.inspect(arg))
    end
    local file = io.open(log_file, "a")
    if file then
      file:write(string.format("[%s] %s %s\n", level, os.date("%H:%M:%S"), table.concat(parts, " ")))
      file:close()
    end
  end
end

return { debug = logger("DEBUG"), info = logger("INFO"), error = logger("ERROR") }
