local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_resource(kbuf, resource, nil, { output = "yaml" })
  end,

  show_yaml = function(kbuf, resource)
    helpers.open_resource(kbuf, resource, nil, { output = "yaml" })
  end,

  describe = function(kbuf, resource)
    helpers.open_resource(kbuf, resource)
  end,

  ---@diagnostic disable-next-line: unused-local
  show_logs = function(kbuf, resource, follow)
    vim.notify(string.format("%s resources do not support logs", resource.kind), vim.log.levels.WARN)
  end,
}

return M
