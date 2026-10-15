local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_pods(kbuf, resource.metadata.namespace, resource.spec.selector.matchLabels)
  end,

  show_logs = function(kbuf, resource, follow)
    helpers.open_resource(kbuf, resource, "logs", follow and { follow = true } or nil)
  end,

  port_forward = function(kbuf, resource)
    helpers.open_resource(kbuf, resource, "portforward")
  end,

  forward_port = function(kbuf, resource)
    helpers.forward_port(kbuf, resource, resource.spec.template.spec.containers)
  end,

  set_image = function(kbuf, resource)
    helpers.set_image(kbuf, resource, resource.spec.template.spec.containers)
  end,

  exec = function(kbuf, resource)
    helpers.exec(kbuf, resource, resource.spec.template.spec.containers)
  end,
}

return M
