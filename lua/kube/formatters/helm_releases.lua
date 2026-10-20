local utils = require("kube.utils")

local HIGHLIGHTS = {
  deployed = "KubeRunning",
  superseded = "KubeSucceeded",
  uninstalled = "KubeSucceeded",
  failed = "KubeFailed",
  unknown = "KubeUnknown",
}

---Helm releases (`helm list`), rows are not Kubernetes objects: they have no `metadata`.
---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "REVISION", "STATUS", "CHART", "APP VERSION", "UPDATED" },
  empty = "No releases found",
}

---The highlight group of a release status.
---@param status string
---@return string
function M.highlight(status)
  return HIGHLIGHTS[status] or "KubePending" -- pending-install, pending-upgrade, uninstalling, ...
end

---@param updated string As helm outputs it, `2026-01-01 08:00:00.1 +0800 CST` or `2026-01-01T08:00:00.1+08:00`
---@return string The time since `updated`
function M.age(updated)
  if type(updated) ~= "string" or not updated:match("^%d%d%d%d%-%d%d%-%d%d.%d%d:%d%d:%d%d") then
    return ""
  end
  local sign, hours, minutes = updated:sub(20):match("([+-])(%d%d):?(%d%d)")
  local offset = sign and (tonumber(hours) * 3600 + tonumber(minutes) * 60) * (sign == "-" and -1 or 1) or 0
  return utils.format_duration(os.difftime(os.time(), utils.parse_time(updated) - offset))
end

function M.format(releases)
  -- By namespace like kubectl lists, helm sorts by name or date only
  table.sort(releases, function(a, b)
    if a.namespace ~= b.namespace then
      return a.namespace < b.namespace
    end
    return a.name < b.name
  end)
  local rows = {}
  for _, release in ipairs(releases) do
    local status = release.status or "unknown"
    local diagnostics = {}
    if status == "failed" then
      table.insert(diagnostics, {
        message = "The release failed, see its history",
        severity = vim.diagnostic.severity.ERROR,
      })
    elseif M.highlight(status) ~= "KubeRunning" and M.highlight(status) ~= "KubeSucceeded" then
      table.insert(diagnostics, {
        message = "The release is " .. status,
        severity = vim.diagnostic.severity.WARN,
      })
    end

    table.insert(rows, {
      row = {
        release.namespace,
        release.name,
        tostring(release.revision),
        status,
        release.chart or "",
        release.app_version or "",
        M.age(release.updated),
      },
      highlights = { STATUS = M.highlight(status) },
      item = {
        kind = "HelmRelease",
        name = release.name,
        namespace = release.namespace,
        revision = tonumber(release.revision),
        status = status,
      },
      diagnostics = diagnostics,
    })
  end
  return rows
end

return M
