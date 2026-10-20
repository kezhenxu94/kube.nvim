---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    vim.cmd.edit(vim.fn.fnameescape(require("kube.navigation").api_resource_target(kbuf, resource)))
  end,
}

return M
