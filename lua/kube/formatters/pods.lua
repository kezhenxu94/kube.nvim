local log = require("kube.log")
local utils = require("kube.utils")
local finished_statuses = { "Completed", "Succeeded" }
local severity_map = {
  Pending = vim.diagnostic.severity.WARN,
  Failed = vim.diagnostic.severity.ERROR,
}

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "IP", "NODE", "AGE" },

  format = function(data)
    local rows = {}
    for _, pod in ipairs(data.items) do
      local name = pod.metadata.name
      local namespace = pod.metadata.namespace
      local status = pod.status.phase
      local highlight = "Kube" .. status

      local ready_count = 0
      local container_count = #pod.spec.containers
      if pod.status.containerStatuses then
        for _, container in ipairs(pod.status.containerStatuses) do
          if container.ready then
            ready_count = ready_count + 1
          end
        end
      end
      local ready = string.format("%d/%d", ready_count, container_count)

      if status == "Running" and ready_count < container_count then
        highlight = "KubePending"
      end

      local restarts = 0
      if pod.status.containerStatuses then
        for _, container in ipairs(pod.status.containerStatuses) do
          restarts = restarts + container.restartCount
        end
      end

      local diagnostics = {}
      if not vim.tbl_contains(finished_statuses, status) and pod.status.conditions then
        if #pod.status.conditions == 1 then
          local condition = pod.status.conditions[1]
          local message = condition.message or condition.reason
          table.insert(diagnostics, {
            message = string.format("The pod is not ready: %s", message),
            severity = severity_map[status] or vim.diagnostic.severity.ERROR,
          })
        end
        log.debug("pod.status.conditions", pod.status.conditions)
        for _, condition in ipairs(pod.status.conditions) do
          if condition.type == "Ready" and condition.status ~= "True" then
            local message = condition.message or condition.reason
            table.insert(diagnostics, {
              message = string.format("The pod is not ready: %s", message),
              severity = severity_map[status] or vim.diagnostic.severity.ERROR,
            })
          end
        end
      end

      table.insert(rows, {
        row = {
          namespace,
          name,
          ready,
          status,
          tostring(restarts),
          pod.status.podIP or "",
          pod.spec.nodeName or "",
          utils.calculate_age(pod.metadata.creationTimestamp),
          highlight = highlight,
        },
        item = pod,
        diagnostics = diagnostics,
      })
    end
    return rows
  end,
}

return M
