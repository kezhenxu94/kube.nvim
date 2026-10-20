local releases = require("kube.formatters.helm_releases")

---The revisions of a Helm release (`helm history`), the latest last as helm lists them.
---@type Formatter
local M = {
  headers = { "REVISION", "UPDATED", "STATUS", "CHART", "APP VERSION", "DESCRIPTION" },
  empty = "No revisions found",

  format = function(revisions, buffer)
    local rows = {}
    for _, revision in ipairs(revisions) do
      table.insert(rows, {
        row = {
          tostring(revision.revision),
          releases.age(revision.updated),
          revision.status or "",
          revision.chart or "",
          revision.app_version or "",
          revision.description or "",
        },
        highlights = { STATUS = releases.highlight(revision.status or "unknown") },
        item = {
          kind = "HelmRevision",
          -- The row's identity, see `renderers.resources`
          name = tostring(revision.revision),
          release = buffer.resource_name,
          namespace = buffer.namespace,
          revision = tonumber(revision.revision),
        },
      })
    end
    return rows
  end,
}

return M
