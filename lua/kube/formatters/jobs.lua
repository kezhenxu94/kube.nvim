local utils = require("kube.utils")

---@param job table
---@param type string
---@return table|nil The condition of `type` that is true
local function condition(job, type)
  for _, c in ipairs(job.status.conditions or {}) do
    if c.type == type and c.status == "True" then
      return c
    end
  end
  return nil
end

---Like the STATUS of `kubectl get jobs`.
---@param job table
---@return string status
---@return string highlight
local function job_status(job)
  if condition(job, "Complete") then
    return "Complete", "KubeSucceeded"
  elseif condition(job, "Failed") then
    return "Failed", "KubeFailed"
  elseif type(job.metadata.deletionTimestamp) == "string" then
    return "Terminating", "KubePending"
  elseif condition(job, "Suspended") then
    return "Suspended", "KubeUnknown"
  end
  return "Running", "KubeRunning"
end

---Like the COMPLETIONS of `kubectl get jobs`.
---@param job table
---@return string
local function completions(job)
  local succeeded = job.status.succeeded or 0
  if type(job.spec.completions) == "number" then
    return string.format("%d/%d", succeeded, job.spec.completions)
  end
  local parallelism = job.spec.parallelism or 1
  if parallelism > 1 then
    return string.format("%d/1 of %d", succeeded, parallelism)
  end
  return string.format("%d/1", succeeded)
end

---@param job table
---@return string
local function duration(job)
  if type(job.status.startTime) ~= "string" then
    return ""
  end
  local finished = type(job.status.completionTime) == "string" and utils.parse_time(job.status.completionTime)
    or os.time()
  return utils.format_duration(os.difftime(finished, utils.parse_time(job.status.startTime)))
end

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "STATUS", "COMPLETIONS", "DURATION", "AGE" },

  format = function(data)
    local rows = {}
    for _, job in ipairs(data.items) do
      local status, highlight = job_status(job)
      local failed = status == "Failed" and condition(job, "Failed")
      table.insert(rows, {
        row = {
          job.metadata.namespace,
          job.metadata.name,
          status,
          completions(job),
          duration(job),
          utils.calculate_age(job.metadata.creationTimestamp),
        },
        highlights = { STATUS = highlight },
        item = job,
        diagnostics = failed and {
          {
            message = failed.message or failed.reason or "The job failed",
            severity = vim.diagnostic.severity.ERROR,
          },
        } or nil,
      })
    end
    return rows
  end,
}

return M
