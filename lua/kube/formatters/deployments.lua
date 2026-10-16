local edits = require("kube.edits")
local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "READY", "DESIRED", "UP-TO-DATE", "AVAILABLE", "AGE" },
  editable = { DESIRED = edits.replicas },

  format = function(data)
    local rows = {}

    for _, item in ipairs(data.items) do
      local ready = string.format("%d/%d", item.status.readyReplicas or 0, item.status.replicas or 0)

      table.insert(rows, {
        row = {
          item.metadata.namespace,
          item.metadata.name,
          ready,
          tostring(item.spec.replicas or 1),
          tostring(item.status.updatedReplicas or 0),
          tostring(item.status.availableReplicas or 0),
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end

    return rows
  end,
}

return M
