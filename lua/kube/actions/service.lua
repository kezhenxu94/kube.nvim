local helpers = require("kube.actions.helpers")

---@type Actions
local M = {
  drill_down_resource = function(kbuf, resource)
    helpers.open_pods(kbuf, resource.metadata.namespace, resource.spec.selector)
  end,

  forward_port = function(kbuf, resource)
    local ports = {}
    for _, port in ipairs(resource.spec.ports or {}) do
      table.insert(ports, { name = port.name, ports = { { containerPort = port.port, protocol = port.protocol } } })
    end
    helpers.forward_port(kbuf, resource, ports)
  end,

  exec = function(kbuf, resource)
    helpers.exec(kbuf, resource, {})
  end,
}

return M
