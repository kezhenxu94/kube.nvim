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

    local buf = vim.api.nvim_create_buf(false, true)
    local buf_name =
      string.format("kube://namespaces/%s/%s/%s/exec", parent.namespace or "default", parent.name, resource.name)
    vim.api.nvim_buf_set_name(buf, buf_name)

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "terminal", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

    vim.api.nvim_set_current_buf(buf)

    local cmd = string.format(
      "kubectl exec -it -n %s %s -c %s -- bash || sh",
      parent.namespace or "default",
      parent.name,
      resource.name
    )
    vim.fn.termopen(cmd)
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.cmd("file " .. buf_name)
    vim.cmd("startinsert")
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
