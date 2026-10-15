local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_pods(kbuf, resource.metadata.namespace, resource.spec.selector.matchLabels)
  end,

  set_image = function(kbuf, resource)
    helpers.set_image(kbuf, resource, resource.spec.template.spec.containers)
  end,
}

return M
