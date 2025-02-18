local log = require("kube.log")

---@type Actions
local M = {
  drill_down_resource = function(resource, _)
    log.debug("drilling down to deployment", resource)

    local namespace = resource.metadata.namespace
    local selector = resource.spec.selector.matchLabels

    local buf_name

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

  show_logs = function(resource, follow, _)
    log.debug("showing logs for deployment", resource.metadata.name, "in namespace", resource.metadata.namespace)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace
    local buf_name
    local params = {}

    if namespace then
      buf_name = string.format("kube://namespaces/%s/%s/%s/logs", namespace, kind, name)
    else
      buf_name = string.format("kube://%s/%s/logs", kind, name)
    end

    if follow then
      table.insert(params, "follow=true")
    end

    buf_name = buf_name .. "?" .. table.concat(params, "&")

    vim.cmd.edit(buf_name)
  end,

  port_forward = function(resource, _)
    log.debug("forwarding port for pod", resource)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace
    local buf_name
    if namespace then
      buf_name = string.format("kube://namespaces/%s/%s/%s/portforward", namespace, kind, name)
    else
      buf_name = string.format("kube://%s/%s/portforward", kind, name)
    end

    vim.cmd.edit(buf_name)
  end,

  forward_port = function(resource, _)
    log.debug("forwarding port for deployment", resource, "in namespace", resource.metadata.namespace)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    local ports = {}
    for _, container in ipairs(resource.spec.template.spec.containers) do
      for _, port in ipairs(container.ports or {}) do
        table.insert(ports, {
          container = container.name,
          port = port.containerPort,
          protocol = port.protocol or "TCP",
        })
      end
    end
    require("kube.utils.portforward").prompt_port_forward(ports, kind, name, namespace)
  end,

  set_image = function(kbuf, resource, _)
    log.debug("setting image for deployment", resource.metadata.name, "in namespace", resource.metadata.namespace)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    local containers = {}
    for _, container in ipairs(resource.spec.template.spec.containers or {}) do
      table.insert(containers, {
        name = container.name,
        image = container.image,
      })
    end
    require("kube.utils.set_image").prompt_set_image(containers, kind, name, namespace, function(changed)
      if changed then
        kbuf:load()
      end
    end)
  end,

  exec = function(resource, _)
    require("kube.utils.exec").prompt_exec(
      resource.spec.template.spec.containers,
      resource.kind,
      resource.metadata.name,
      resource.metadata.namespace
    )
  end,
}

return M
