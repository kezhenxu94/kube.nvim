local utils = require("kube.utils")

---@param event table
---@return string
local function last_seen(event)
  local time = event.lastTimestamp ~= vim.NIL and event.lastTimestamp
    or event.eventTime ~= vim.NIL and event.eventTime
    or event.metadata.creationTimestamp
  return time or ""
end

---@type Formatter
local M = {
  headers = { "NAMESPACE", "LAST SEEN", "TYPE", "REASON", "OBJECT", "MESSAGE" },
  -- Events of an object are only kept for a while (--event-ttl, 1h by default)
  empty = "No events: Kubernetes keeps events for 1 hour by default",

  format = function(data)
    local events = vim.list_extend({}, data.items)
    -- Most recent first; ISO timestamps sort lexicographically
    table.sort(events, function(a, b)
      return last_seen(a):sub(1, 19) > last_seen(b):sub(1, 19)
    end)

    local rows = {}
    for _, event in ipairs(events) do
      local object = event.involvedObject or {}
      local message = (event.message or ""):gsub("%s*\n%s*", " ")
      local warning = event.type == "Warning"
      local seen = last_seen(event)

      table.insert(rows, {
        row = {
          event.metadata.namespace or "",
          seen ~= "" and utils.calculate_age(seen) or "",
          event.type or "",
          event.reason or "",
          string.format("%s/%s", (object.kind or ""):lower(), object.name or ""),
          message,
          highlight = warning and "KubePending" or "KubeBody",
        },
        item = event,
        diagnostics = warning and { { message = message, severity = vim.diagnostic.severity.WARN } } or nil,
      })
    end
    return rows
  end,
}

return M
