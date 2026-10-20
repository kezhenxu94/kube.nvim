---The resource types of `kubectl api-resources`, rows open the list of their type.
---@type Formatter
local M = {
  headers = { "NAME", "SHORTNAMES", "APIVERSION", "NAMESPACED", "KIND" },

  format = function(resources)
    local rows = {}
    for _, resource in ipairs(resources) do
      local group = resource.apiversion:match("^(.+)/[^/]+$")
      table.insert(rows, {
        row = { resource.name, resource.shortnames, resource.apiversion, resource.namespaced, resource.kind },
        -- Group qualified, so kubectl never picks a same-named type of another API group
        item = {
          kind = "APIResource",
          name = group and resource.name .. "." .. group or resource.name,
          namespaced = resource.namespaced == "true",
          -- The kind of its objects, e.g. Deployment
          object_kind = resource.kind,
        },
      })
    end
    return rows
  end,
}

return M
