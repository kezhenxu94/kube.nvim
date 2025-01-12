---@class Highlights
---@field KubeBody table<string, any>
---@field KubePending table<string, any>
---@field KubeRunning table<string, any>
---@field KubeFailed table<string, any>
---@field KubeSucceeded table<string, any>
---@field KubeUnknown table<string, any>
---@field KubeHeader table<string, any>

local M = {}

---@type Highlights
local default_highlights = {
  KubeBody = { fg = "#40a02b" },
  KubePending = { fg = "#fe640b" },
  KubeRunning = { fg = "#40a02b" },
  KubeFailed = { fg = "#d20f39" },
  KubeSucceeded = { fg = "#9ca0b0" },
  KubeUnknown = { fg = "#6c6f85" },
  KubeHeader = { fg = "#df8e1d", bold = true },
}

function M.setup(opts)
  opts = opts or {}
  local highlights = vim.tbl_deep_extend("force", default_highlights, opts.highlights or {})

  for group, colors in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, colors)
  end
end

return M
