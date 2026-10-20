local formatters = require("kube.formatters")

---Parse the `kubectl api-resources` table by the columns of its header, SHORTNAMES may be empty.
---@param output string
---@return {name: string, shortnames: string, apiversion: string, namespaced: string, kind: string}[]
local function parse(output)
  local lines = vim.split(output, "\n", { trimempty = true })
  local header = table.remove(lines, 1) or ""
  local columns = {}
  for start, column in header:gmatch("()(%S+)") do
    table.insert(columns, { start = start, key = column:lower() })
  end

  local resources = {}
  for _, line in ipairs(lines) do
    local resource = {}
    for i, column in ipairs(columns) do
      local next_column = columns[i + 1]
      resource[column.key] = vim.trim(line:sub(column.start, next_column and next_column.start - 1 or -1))
    end
    table.insert(resources, resource)
  end
  return resources
end

---The resource types of the cluster, to pick one to list.
---@type Renderer
local M = {
  load = function(buffer)
    return require("kubectl").api_resources(buffer.context, function(result, code, stderr)
      if not result or not vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
        return
      end
      require("kube.renderers.resources").render(buffer, formatters["api-resources"], parse(result))
      -- Exits with 1 when some API groups fail, e.g. an unavailable metrics server, listing the others
      if code ~= 0 then
        buffer:on_error()(stderr)
      end
    end, buffer:on_error())
  end,
}

return M
