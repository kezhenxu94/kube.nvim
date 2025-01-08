local utils = require("kube.utils")

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

      if ready_count < container_count then
        highlight = "KubePending"
      end

      local restarts = 0
      if pod.status.containerStatuses then
        for _, container in ipairs(pod.status.containerStatuses) do
          restarts = restarts + container.restartCount
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
      })
    end
    return rows
  end,
}

return M
