local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  set_image = function(kbuf, resource)
    helpers.set_image(kbuf, resource, resource.spec.jobTemplate.spec.template.spec.containers)
  end,
}

return M
