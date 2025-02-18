---@class KubeConfig
---@field keymaps table<string, string>|nil
---@field highlights Highlights|nil
local M = {}

---@return KubeConfig
function M.defaults()
  return {
    keymaps = {
      drill_down = "<cr>",
      describe = "gd",
      refresh = "gr",
      show_logs = "gl",
      follow_logs = "gL",
      port_forward = "gF",
      forward_port = "gf",
      show_yaml = "gy",
      edit = "ge",
      set_image = "gi",
      quit = "q",
      exec = "gE",
    },
  }
end

M.values = M.defaults()

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", M.defaults(), opts)
end

return M
