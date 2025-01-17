local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "DESIRED", "CURRENT", "READY", "AVAILABLE", "AGE" },

  format = function(data)
    local rows = {}
    for _, item in ipairs(data.items) do
      table.insert(rows, {
        row = {
          item.metadata.namespace,
          item.metadata.name,
          tostring(item.status.desiredNumberScheduled),
          tostring(item.status.currentNumberScheduled),
          tostring(item.status.numberReady),
          tostring(item.status.numberAvailable or 0),
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end
    return rows
  end,
}

return M
