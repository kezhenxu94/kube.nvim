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
          item.metadata.namespace or "",
          item.metadata.name,
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end
    return rows
  end,
}

return M
