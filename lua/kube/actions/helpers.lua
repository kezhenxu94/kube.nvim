local utils = require("kube.utils")

local M = {}

---Open a buffer for the resource, in the context of the buffer it was selected from.
---@param kbuf KubeBuffer
---@param resource table
---@param subresource string|nil
---@param params table<string, any>|nil
function M.open_resource(kbuf, resource, subresource, params)
  utils.open({
    context = kbuf.context,
    namespace = resource.metadata.namespace,
    kind = utils.resource_type(resource),
    name = resource.metadata.name,
    subresource = subresource,
    params = params,
  })
end

---Open the pods matching the label selector.
---@param kbuf KubeBuffer
---@param namespace string|nil
---@param selector table<string, string>|nil
function M.open_pods(kbuf, namespace, selector)
  local labels = {}
  for key, value in pairs(selector or {}) do
    table.insert(labels, string.format("%s=%s", key, value))
  end
  table.sort(labels)

  utils.open({
    context = kbuf.context,
    namespace = namespace,
    kind = "pods",
    params = #labels > 0 and { selector = table.concat(labels, ",") } or nil,
  })
end

---@param kbuf KubeBuffer
---@param resource table
---@param containers table[]|nil The container specs
function M.set_image(kbuf, resource, containers)
  local items = {}
  for _, container in ipairs(containers or {}) do
    table.insert(items, { name = container.name, image = container.image })
  end
  require("kube.utils.set_image").prompt_set_image(
    kbuf.context,
    items,
    utils.resource_type(resource),
    resource.metadata.name,
    resource.metadata.namespace,
    function(changed)
      if changed then
        kbuf:load()
      end
    end
  )
end

---@param kbuf KubeBuffer
---@param resource table
---@param containers table[]|nil The container specs
function M.forward_port(kbuf, resource, containers)
  local ports = {}
  for _, container in ipairs(containers or {}) do
    for _, port in ipairs(container.ports or {}) do
      table.insert(ports, {
        container = container.name,
        port = port.containerPort,
        protocol = port.protocol or "TCP",
      })
    end
  end
  require("kube.utils.portforward").prompt_port_forward(
    kbuf.context,
    ports,
    utils.resource_type(resource),
    resource.metadata.name,
    resource.metadata.namespace
  )
end

---@param kbuf KubeBuffer
---@param resource table
---@param containers table[]|nil The container specs
function M.exec(kbuf, resource, containers)
  require("kube.utils.exec").prompt_exec(
    kbuf.context,
    containers or {},
    utils.resource_type(resource),
    resource.metadata.name,
    resource.metadata.namespace
  )
end

return M
