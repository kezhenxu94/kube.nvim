local constants = require("kube.constants")
local utils = require("kube.utils")

local M = {}

---The buffer one level up: subresource / resource -> list in its namespace
----> list in all namespaces -> namespaces -> api-resources.
---@param kbuf KubeBuffer
---@return string|nil
function M.parent_name(kbuf)
  if kbuf.resource_name then
    return utils.buf_name({ context = kbuf.context, namespace = kbuf.namespace, kind = kbuf.resource_kind })
  end
  if kbuf.namespace ~= "all" then
    return utils.buf_name({ context = kbuf.context, kind = kbuf.resource_kind, params = kbuf.params })
  end
  if kbuf.resource_kind == "namespaces" then
    return utils.buf_name({ context = kbuf.context, kind = "api-resources" })
  end
  if kbuf.resource_kind ~= "api-resources" then
    return utils.buf_name({ context = kbuf.context, kind = "namespaces" })
  end
  return nil
end

---The list of the resource type of an `api-resources` row, in the buffer's namespace if namespaced.
---@param kbuf KubeBuffer
---@param item table
---@return string
function M.api_resource_target(kbuf, item)
  return utils.buf_name({
    context = kbuf.context,
    namespace = item.namespaced and kbuf.namespace or nil,
    kind = item.name,
  })
end

---The cell at `pos`, or just the row's item between cells.
---@param kbuf KubeBuffer
---@param pos integer[] (0,0)-indexed position
---@return {item: table, column: string|nil}|nil
local function cell_at(kbuf, pos)
  local marks =
    vim.api.nvim_buf_get_extmarks(kbuf.buf_nr, constants.KUBE_COLUMN_NAMESPACE, pos, pos, { overlap = true })
  for _, mark in ipairs(marks) do
    local column = kbuf.mark_columns[mark[1]]
    if column then
      return column
    end
  end

  local row_marks = vim.api.nvim_buf_get_extmarks(
    kbuf.buf_nr,
    constants.KUBE_NAMESPACE,
    { pos[1], 0 },
    { pos[1], -1 },
    {}
  )
  local marked_line = row_marks[1] and kbuf.mark_mappings[row_marks[1][1]]
  return marked_line and { item = marked_line.item }
end

---The buffer the cell at `pos` refers to, like a tag:
---NAMESPACE -> the same list in that namespace, NODE -> the node, an event's OBJECT -> that object,
---a namespace row -> its pods, a resource type -> its list, anything else -> the resource's definition (YAML).
---@param kbuf KubeBuffer
---@param pos integer[] (0,0)-indexed position
---@return string|nil
function M.tag_target(kbuf, pos)
  local cell = cell_at(kbuf, pos)
  local item = cell and cell.item
  if item and item.kind == "APIResource" then
    return M.api_resource_target(kbuf, item)
  end
  if not item or not item.metadata then
    return nil
  end

  if cell.column == "NAMESPACE" and item.metadata.namespace and not kbuf.resource_name then
    return utils.buf_name({
      context = kbuf.context,
      namespace = item.metadata.namespace,
      kind = kbuf.resource_kind,
      params = kbuf.params,
    })
  end
  if cell.column == "OBJECT" and item.involvedObject then
    local object = item.involvedObject
    return utils.buf_name({
      context = kbuf.context,
      namespace = object.namespace,
      kind = utils.resource_type(object),
      name = object.name,
      params = { output = "yaml" },
    })
  end
  if cell.column == "NODE" and item.spec and item.spec.nodeName then
    return utils.buf_name({ context = kbuf.context, kind = "node", name = item.spec.nodeName })
  end
  if item.kind == "Namespace" then
    return utils.buf_name({ context = kbuf.context, namespace = item.metadata.name, kind = "pods" })
  end
  return utils.buf_name({
    context = kbuf.context,
    namespace = item.metadata.namespace,
    kind = utils.resource_type(item),
    name = item.metadata.name,
    params = { output = "yaml" },
  })
end

---'tagfunc' for kube buffers, so <C-]>, <C-w>], <C-t> and the tag stack work as usual.
---@param pattern string
---@param flags string
---@return table[]|vim.NIL
function M.tagfunc(pattern, flags)
  local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
  -- Only jumps from the cursor are resolved here, `:tag {name}` uses the tags files
  if not kbuf or not flags:find("c", 1, true) then
    return vim.NIL
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local target = M.tag_target(kbuf, { cursor[1] - 1, cursor[2] })
  if not target then
    return {}
  end
  return { { name = pattern, filename = target, cmd = "1" } }
end

return M
