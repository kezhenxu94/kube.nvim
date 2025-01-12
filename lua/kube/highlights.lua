local M = {}

local highlights = {
  KubeBody = { fg = "#40a02b" },
  KubePending = { fg = "#fe640b" },
  KubeRunning = { fg = "#40a02b" },
  KubeFailed = { fg = "#d20f39" },
  KubeSucceeded = { fg = "#9ca0b0" },
  KubeUnknown = { fg = "#6c6f85" },
  KubeHeader = { fg = "#df8e1d", bold = true },
}

function M.setup()
  for group, colors in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, colors)
  end
end

return M
