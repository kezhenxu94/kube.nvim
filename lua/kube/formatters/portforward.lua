local log = require("kube.log")

---@type Formatter
local M = {
  headers = { "NAME", "CONTAINER", "PORTS", "URL" },

  format = function(parent_resource)
    local rows = {}

    local namespace = parent_resource.metadata.namespace
    local name = parent_resource.metadata.name
    local portforwards = _G.portforwards[string.format("%s/%s", namespace, name)] or {}

    for _, container in ipairs(parent_resource.spec.containers) do
      local ports = {}
      local urls = {}
      for _, port in ipairs(container.ports or {}) do
        local container_port = port.containerPort
        for local_port, portforward in pairs(portforwards) do
          if portforward.container_port == container_port then
            table.insert(ports, string.format("%d:%d", local_port, container_port))
            table.insert(urls, string.format("localhost:%d", local_port))
          end
        end
      end

      table.insert(rows, {
        row = {
          name,
          container.name,
          table.concat(ports, ","),
          table.concat(urls, ","),
        },
        item = parent_resource,
      })
    end

    return rows
  end,
}

return M
