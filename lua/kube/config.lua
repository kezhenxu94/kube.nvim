---@class KubeConfig
---@field keymaps table<string, string>|nil
---@field refresh_interval integer|false|nil
---@field request_timeout string|nil
---@field logs {tail: integer, max_lines: integer}|nil
---@field highlights Highlights|nil
local M = {}

---@return KubeConfig
function M.defaults()
  return {
    -- Follows Neovim's conventions: LSP (gd, K, <C-]> via 'tagfunc') and the
    -- built-in directory browser (<CR>, -, R)
    keymaps = {
      drill_down = "<cr>",
      show_yaml = "gd",
      describe = "K",
      parent = "-",
      refresh = "R",
      watch = "gw",
      show_logs = "gl",
      follow_logs = "gL",
      port_forward = "gF",
      forward_port = "gf",
      set_image = "gi",
      exec = "gs",
      help = "g?",
    },
    -- How often watched lists (toggled with `gw`) reload, in milliseconds, false to disable watching
    refresh_interval = 10000,
    -- kubectl --request-timeout for everything except streams (logs -f, port-forward, exec, drain)
    request_timeout = "30s",
    logs = {
      -- Number of lines to fetch, -1 for all
      tail = 1000,
      -- Lines kept while following, the oldest are dropped, -1 for all
      max_lines = 10000,
    },
  }
end

M.values = M.defaults()

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", M.defaults(), opts)
end

return M
