local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "RESOURCE", "LOCAL_PORT", "CONTAINER_PORT", "URL" },

  format = function(parent_resource, buffer)
    local rows = {}

    local namespace = parent_resource.metadata.namespace
    local resource_type = utils.resource_type(parent_resource)
    local name = parent_resource.metadata.name
    local key = utils.portforward_key(buffer.context, namespace, resource_type, name)

    for local_port, portforward in pairs(_G.portforwards[key] or {}) do
      table.insert(rows, {
        row = {
          namespace,
          string.format("%s/%s", parent_resource.kind, name),
          tostring(local_port),
          tostring(portforward.container_port),
          string.format("http://localhost:%d", local_port),
        },
        item = {
          id = key,
          portforward = portforward,
          local_port = local_port,
        },
      })
    end

    table.sort(rows, function(a, b)
      return a.item.local_port < b.item.local_port
    end)

    return rows
  end,
}

return M
