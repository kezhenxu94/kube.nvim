local log = require("kube.log")

---@type Actions
local M = {
  drill_down_resource = function(resource, parent)
    log.debug("drilling down to deployment", resource)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace
    local selector = resource.spec.selector.matchLabels

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

  show_logs = function(resource, follow, parent)
    if not parent then
      log.error("parent resource is required")
      return
    end

    log.debug("showing logs for container", resource.name, "in pod", parent.name)

    local kind = parent.kind:lower()
    local name = parent.name
    local namespace = parent.namespace
    local buf_name
    local params = {}

    if namespace then
      buf_name = string.format("kube://namespaces/%s/%s/%s/logs", namespace, kind, name)
    else
      buf_name = string.format("kube://%s/%s/logs", kind, name)
    end

    table.insert(params, "container=" .. resource.name)

    if follow then
      table.insert(params, "follow=true")
    end

    buf_name = buf_name .. "?" .. table.concat(params, "&")

    vim.cmd.edit(buf_name)
  end,

  forward_port = function(resource, parent)
    log.debug("forwarding port for container", resource, "in pod", parent.name)

    local kind = parent.kind:lower()
    local name = parent.name
    local namespace = parent.namespace

    local ports = {}
    for _, port in ipairs(resource.ports or {}) do
      table.insert(ports, {
        container = resource.name,
        port = port.containerPort,
        protocol = port.protocol or "TCP",
      })
    end
    require("kube.utils.portforward").prompt_port_forward(ports, kind, name, namespace)
  end,
}

return M
