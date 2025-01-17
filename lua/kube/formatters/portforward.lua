local log = require("kube.log")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "RESOURCE", "LOCAL_PORT", "CONTAINER_PORT", "URL" },

  format = function(parent_resource)
    local rows = {}

    local namespace = parent_resource.metadata.namespace
    local resource_kind = parent_resource.kind
    local name = parent_resource.metadata.name
    local portforwards = _G.portforwards[string.format("%s/%s", namespace, name)] or {}

    for local_port, portforward in pairs(portforwards) do
      table.insert(rows, {
        row = {
          namespace,
          string.format("%s/%s", resource_kind, name),
          tostring(local_port),
          tostring(portforward.container_port),
          string.format("localhost:%d", local_port),
        },
        item = {
          id = string.format("%s/%s", namespace, name),
          portforward = portforward,
          local_port = local_port,
        },
      })
    end

    return rows
  end,
}

return M
