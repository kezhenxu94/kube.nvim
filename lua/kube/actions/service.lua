local log = require("kube.log")

---@type Actions
local M = {
  drill_down_resource = function(resource, parent)
    log.debug("drilling down to service", resource)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace
    local selector = resource.spec.selector

    local buf_name
    local params = {}

    if namespace then
      buf_name = string.format("kube://namespaces/%s/pods", namespace)
    else
      buf_name = string.format("kube://pods")
    end

    local selector_params = {}
    for key, value in pairs(selector) do
      table.insert(selector_params, string.format("%s=%s", key, value))
    end

    if #selector_params > 0 then
      buf_name = buf_name .. "?selector=" .. table.concat(selector_params, ",")
    end

    vim.cmd.edit(buf_name)
  end,

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

  exec = function(resource, parent)
    require("kube.utils.exec").prompt_exec({}, resource.kind, resource.metadata.name, resource.metadata.namespace)
  end,
}

return M
