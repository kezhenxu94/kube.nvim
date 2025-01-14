local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "SCHEDULE", "SUSPENDED", "LAST SCHEDULE", "AGE" },

  format = function(data)
    local rows = {}
    for _, item in ipairs(data.items) do
      table.insert(rows, {
        row = {
          item.metadata.namespace,
          item.metadata.name,
          item.spec.schedule,
          tostring(item.spec.suspend),
          item.status.lastScheduleTime or "<none>",
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end
    return rows
  end,
}

return M
