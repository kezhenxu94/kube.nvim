---@class KubeConfig
---@field keymaps table<string, string>|nil
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
      show_logs = "gl",
      follow_logs = "gL",
      port_forward = "gF",
      forward_port = "gf",
      set_image = "gi",
      exec = "gs",
      quit = "q",
      help = "g?",
    },
  }
end

M.values = M.defaults()

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", M.defaults(), opts)
end

return M
