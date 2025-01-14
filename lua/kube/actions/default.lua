local KubeBuffer = require("kube.buffer").KubeBuffer

---@param resource table
---@param output string|nil
local show_resource = function(resource, output)
  local kind = resource.kind
  local name = resource.metadata.name
  local namespace = resource.metadata.namespace

  local buf_name
  if namespace then
    buf_name = string.format("kube://namespaces/%s/%s/%s", namespace, kind:lower(), name)
  else
    buf_name = string.format("kube://%s/%s", string.lower(kind), name)
  end

  if output then
    buf_name = buf_name .. "?output=" .. output
  end

  vim.cmd.edit(buf_name)
end

---@type Actions
local M = {
  drill_down_resource = function(resource, parent)
    show_resource(resource, "yaml")
  end,

  show_yaml = function(resource, parent)
    show_resource(resource, "yaml")
  end,

  describe = function(resource, parent)
    show_resource(resource, nil)
  end,

  delete = function(resource, parent)
    local kind = resource.kind
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    require("kubectl").delete(kind, name, namespace)
  end,

  ---@diagnostic disable-next-line: unused-local
  show_logs = function(resource, follow, parent)
    local kind = resource.kind

    vim.notify(string.format("%s resources do not support logs", kind), vim.log.levels.WARN)
  end,
}

return M
