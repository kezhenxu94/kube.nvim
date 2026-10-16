---@class Highlights
---@field KubeBody table<string, any>
---@field KubePending table<string, any>
---@field KubeRunning table<string, any>
---@field KubeFailed table<string, any>
---@field KubeSucceeded table<string, any>
---@field KubeUnknown table<string, any>
---@field KubeHeader table<string, any>

local M = {}

---Linked with `default`, so colorschemes and `:highlight` take precedence.
---@type Highlights
local default_highlights = {
  KubeBody = { link = "Normal" },
  KubePending = { link = "DiagnosticWarn" },
  KubeRunning = { link = "Normal" },
  KubeFailed = { link = "DiagnosticError" },
  KubeSucceeded = { link = "Comment" },
  KubeUnknown = { link = "Comment" },
  KubeHeader = { link = "Title" },
}

---@type Highlights
local user_highlights = {}

---@param opts {highlights: Highlights|nil}|nil Overrides, kept for later calls without opts (ColorScheme)
function M.setup(opts)
  if opts and opts.highlights then
    user_highlights = opts.highlights
  end

  for group, hl in pairs(default_highlights) do
    vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", hl, { default = true }))
  end
  for group, hl in pairs(user_highlights) do
    vim.api.nvim_set_hl(0, group, hl)
  end
end

return M
