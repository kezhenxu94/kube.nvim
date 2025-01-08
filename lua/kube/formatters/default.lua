local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = {
    "NAMESPACE",
    "NAME",
    "AGE",
  },

  format = function(data)
    local rows = {}
    for _, item in ipairs(data.items) do
      table.insert(rows, {
        row = {
          item.metadata.name,
          item.metadata.namespace,
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end
    return rows
  end,
}

return M
