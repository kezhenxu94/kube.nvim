---@param resource table
---@param params table?
local show_resource = function(resource, params)
  local kind = resource.kind
  local name = resource.metadata.name
  local namespace = resource.metadata.namespace

  local buf_name
  if namespace then
    buf_name = string.format("kube://namespaces/%s/%s/%s", namespace, kind:lower(), name)
  else
    buf_name = string.format("kube://%s/%s", string.lower(kind), name)
  end

  if params and next(params) then
    local query_params = {}
    for key, value in pairs(params) do
      table.insert(query_params, key .. "=" .. tostring(value))
    end
    buf_name = buf_name .. "?" .. table.concat(query_params, "&")
  end

  vim.cmd.edit(buf_name)
end

---@type Actions
local M = {
  drill_down_resource = function(resource, _)
    show_resource(resource, { output = "yaml" })
  end,

  show_yaml = function(resource, _)
    show_resource(resource, { output = "yaml" })
  end,

  describe = function(resource, _)
    show_resource(resource, nil)
  end,

  edit = function(resource, _)
    show_resource(resource, { output = "yaml", edit = true })
  end,

  delete = function(resource, _)
    local kind = resource.kind
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    require("kubectl").delete(kind, name, namespace, nil, nil)
  end,

  ---@diagnostic disable-next-line: unused-local
  show_logs = function(resource, follow, parent)
    local kind = resource.kind

    vim.notify(string.format("%s resources do not support logs", kind), vim.log.levels.WARN)
  end,
}

return M
