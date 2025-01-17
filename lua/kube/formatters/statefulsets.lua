local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "READY", "SERVICE", "AGE" },

  format = function(data)
    local rows = {}

    for _, item in ipairs(data.items) do
      local ready = string.format("%d/%d", item.status.readyReplicas or 0, item.status.replicas or 0)

      table.insert(rows, {
        row = {
          item.metadata.namespace,
          item.metadata.name,
          ready,
          item.spec.serviceName,
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end

    return rows
  end,
}

return M
