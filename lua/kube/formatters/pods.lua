local pod_status = require("kube.formatters.status")
local utils = require("kube.utils")
local finished_statuses = { Completed = true, Succeeded = true }
local severity_map = {
  Pending = vim.diagnostic.severity.WARN,
  Failed = vim.diagnostic.severity.ERROR,
}

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "IP", "NODE", "AGE" },
  metrics = "pods",

  format = function(data)
    local rows = {}
    for _, pod in ipairs(data.items) do
      local name = pod.metadata.name
      local namespace = pod.metadata.namespace
      local phase = pod.status.phase
      local status = pod_status.pod(pod)
      local highlights = { STATUS = pod_status.highlight(status) }

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
        highlights.READY = "KubePending"
      end

      local restarts = 0
      if pod.status.containerStatuses then
        for _, container in ipairs(pod.status.containerStatuses) do
          restarts = restarts + container.restartCount
        end
      end
      if restarts > 0 then
        highlights.RESTARTS = "KubePending"
      end

      local severity
      if status == "Terminating" then
        severity = vim.diagnostic.severity.INFO
      elseif highlights.STATUS == "KubeFailed" then
        severity = vim.diagnostic.severity.ERROR
      else
        severity = severity_map[phase] or vim.diagnostic.severity.ERROR
      end

      local diagnostics = {}
      if not finished_statuses[status] then
        local conditions = pod.status.conditions
        if conditions then
          for _, condition in ipairs(conditions) do
            -- A single condition is the reason the pod is not ready yet, e.g. it cannot be scheduled
            if (#conditions == 1 or condition.type == "Ready") and condition.status ~= "True" then
              table.insert(diagnostics, {
                message = string.format("The pod is not ready: %s", condition.message or condition.reason),
                severity = severity,
              })
            end
          end
        elseif pod.status.message then
          table.insert(diagnostics, { message = pod.status.message, severity = severity })
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
        },
        highlights = highlights,
        item = pod,
        diagnostics = diagnostics,
      })
    end
    return rows
  end,
}

return M
