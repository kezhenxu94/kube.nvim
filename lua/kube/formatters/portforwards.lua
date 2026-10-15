---All port forwards, across resources and contexts.
---@type Formatter
local M = {
  headers = { "CONTEXT", "NAMESPACE", "RESOURCE", "LOCAL_PORT", "CONTAINER_PORT", "URL" },

  format = function()
    local rows = {}
    for key, forwards in pairs(_G.portforwards) do
      for local_port, portforward in pairs(forwards) do
        table.insert(rows, {
          row = {
            portforward.context,
            portforward.namespace,
            string.format("%s/%s", portforward.resource_type, portforward.name),
            tostring(local_port),
            tostring(portforward.container_port),
            string.format("http://localhost:%d", local_port),
          },
          item = { id = key, portforward = portforward, local_port = local_port },
        })
      end
    end

    table.sort(rows, function(a, b)
      return a.item.local_port < b.item.local_port
    end)
    return rows
  end,
}

return M
