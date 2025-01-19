local log = require("kube.log")

---@type Actions
local M = {
  drill_down_resource = function(resource, parent)
    log.debug("drilling down to container", resource)

    if not parent then
      log.error("parent resource is required")
      return
    end
    if not parent.name then
      log.error("parent resource name is required")
      return
    end

    require("kube.utils.exec").prompt_exec({ resource }, parent.kind, parent.name, parent.namespace)
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
    if not parent then
      log.error("parent resource is required")
      return
    end
    log.debug("forwarding port for container", resource, "in pod", parent.name)

    local kind = parent.kind:lower()
    local name = parent.name
    local namespace = parent.namespace

    if not name or not namespace then
      log.error("parent resource name and namespace are required")
      return
    end

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

  exec = function(resource, parent)
    if not parent then
      log.error("parent resource is required")
      return
    end
    if not parent.name then
      log.error("parent resource name is required")
      return
    end

    require("kube.utils.exec").prompt_exec({ resource }, parent.kind, parent.name, parent.namespace)
  end,
}

return M
