local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_pods(kbuf, resource.metadata.namespace, resource.spec.selector.matchLabels)
  end,

  show_logs = function(kbuf, resource, follow)
    helpers.open_resource(kbuf, resource, "logs", follow and { follow = true } or nil)
  end,
}

return M
