local utils = require("kube.utils")

---Container rows live in the `kube://context/<context>/namespaces/<ns>/pod/<name>/containers` buffer,
---so the buffer itself identifies the parent pod.
---@param kbuf KubeBuffer
---@param container table The container spec
local function exec(kbuf, container)
  require("kube.utils.exec").prompt_exec(
    kbuf.context,
    { container },
    kbuf.resource_kind,
    kbuf.resource_name,
    kbuf.namespace
  )
end

---@type Actions
local M = {
  drill_down_resource = exec,

  show_logs = function(kbuf, container, follow)
    utils.open({
      context = kbuf.context,
      namespace = kbuf.namespace,
      kind = kbuf.resource_kind,
      name = kbuf.resource_name,
      subresource = "logs",
      params = { container = container.name, follow = follow or nil },
    })
  end,

  forward_port = function(kbuf, container)
    local ports = {}
    for _, port in ipairs(container.ports or {}) do
      table.insert(ports, { container = container.name, port = port.containerPort, protocol = port.protocol or "TCP" })
    end
    require("kube.utils.portforward").prompt_port_forward(
      kbuf.context,
      ports,
      -- Normalized from the loaded pod (e.g. `pods` -> `pod`) to match the port forward buffer's key
      kbuf.data and utils.resource_type(kbuf.data) or kbuf.resource_kind,
      kbuf.resource_name,
      kbuf.namespace
    )
  end,

  exec = exec,
}

return M
