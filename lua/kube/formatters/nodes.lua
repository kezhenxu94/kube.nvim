local utils = require("kube.utils")

---Like the STATUS of `kubectl get nodes`: Ready, NotReady or Unknown, and whether it is cordoned.
---@param node table
---@return string
local function node_status(node)
  local status = "Unknown"
  for _, condition in ipairs(node.status.conditions or {}) do
    if condition.type == "Ready" then
      status = condition.status == "True" and "Ready" or condition.status == "False" and "NotReady" or "Unknown"
    end
  end
  if node.spec and node.spec.unschedulable then
    status = status .. ",SchedulingDisabled"
  end
  return status
end

---@type Formatter
local M = {
  headers = { "NAME", "STATUS", "ROLES", "AGE", "VERSION" },
  metrics = "nodes",

  format = function(data)
    local rows = {}
    for _, item in ipairs(data.items) do
      local roles = {}
      for label, _ in pairs(item.metadata.labels or {}) do
        if label:match("^node%-role.kubernetes.io/") then
          table.insert(roles, label:match("node%-role.kubernetes.io/(.+)"))
        end
      end
      table.sort(roles)

      local status = node_status(item)
      local ready = vim.startswith(status, "Ready")
      table.insert(rows, {
        row = {
          item.metadata.name,
          status,
          table.concat(roles, ","),
          utils.calculate_age(item.metadata.creationTimestamp),
          item.status.nodeInfo.kubeletVersion,
        },
        highlights = { STATUS = status == "Ready" and "KubeRunning" or ready and "KubePending" or "KubeFailed" },
        item = item,
        diagnostics = not ready
            and { { message = "The node is " .. status, severity = vim.diagnostic.severity.ERROR } }
          or nil,
      })
    end
    return rows
  end,
}

return M
