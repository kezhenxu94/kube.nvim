local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_resource(kbuf, resource, "data")
  end,
}

return M
