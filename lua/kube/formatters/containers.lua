local status = require("kube.formatters.status")

---@param container table The container spec
---@return string
local function ports(container)
  local port_strings = {}
  for _, port in ipairs(container.ports or {}) do
    table.insert(port_strings, string.format("%d/%s", port.containerPort, port.protocol or "TCP"))
  end
  return table.concat(port_strings, ", ")
end

---@type Formatter
local M = {
  headers = { "NAME", "TYPE", "STATUS", "RESTARTS", "IMAGE", "PORTS" },
  editable = { IMAGE = require("kube.edits").image },

  format = function(pod)
    local pod_status = pod.status or {}
    local rows = {}

    ---@param containers table[]|nil The container specs
    ---@param statuses table[]|nil Their statuses
    ---@param type fun(container: table): string
    local function add(containers, statuses, type)
      local by_name = {}
      for _, container_status in ipairs(statuses or {}) do
        by_name[container_status.name] = container_status
      end
      for _, container in ipairs(containers or {}) do
        local container_status = by_name[container.name]
        local text, highlight = status.container(container_status)
        local restarts = container_status and container_status.restartCount or 0
        table.insert(rows, {
          row = { container.name, type(container), text, tostring(restarts), container.image, ports(container) },
          highlights = { STATUS = highlight, RESTARTS = restarts > 0 and "KubePending" or nil },
          item = container,
        })
      end
    end

    -- In the order they start
    add(pod.spec.initContainers, pod_status.initContainerStatuses, function(container)
      return container.restartPolicy == "Always" and "sidecar" or "init"
    end)
    add(pod.spec.containers, pod_status.containerStatuses, function()
      return "main"
    end)
    return rows
  end,
}

return M
