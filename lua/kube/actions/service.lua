local log = require("kube.log")

---@type Actions
local M = {
  forward_port = function(resource, parent)
    log.debug("forwarding port for service", resource, "in namespace", resource.metadata.namespace)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    local ports = {}
    for _, port in ipairs(resource.spec.ports or {}) do
      table.insert(ports, {
        container = port.name,
        port = port.port,
        protocol = port.protocol or "TCP",
      })
    end
    require("kube.utils.portforward").prompt_port_forward(ports, kind, name, namespace)
  end,
}

return M
