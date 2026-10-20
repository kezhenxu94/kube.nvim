local constants = require("kube.constants")
local log = require("kube.log")
local utils = require("kube.utils")

---@param resource table
---@return string
local function describe_target(resource)
  return string.format("%s: %s/%s", utils.resource_type(resource), resource.metadata.namespace, resource.metadata.name)
end

---@param buffer KubeBuffer
---@param row_mark integer
---@return boolean Whether the row was deleted
local function deleted(buffer, row_mark)
  local mark = vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_NAMESPACE, row_mark, { details = true })
  return #mark == 3 and mark[3] and mark[3].invalid == true
end

---The edits of the cells of editable columns, and the errors of the invalid ones and of the other edited cells.
---@param buffer KubeBuffer
---@return KubeEdit[] edits
---@return string[] errors
local function cell_edits(buffer)
  local edits, errors = {}, {}
  local editable = require("kube.renderers.resources").formatter_for(buffer).editable or {}

  -- Marks are created in the order of the cells
  local ids = vim.tbl_keys(buffer.mark_columns)
  table.sort(ids)
  for _, id in ipairs(ids) do
    local cell = buffer.mark_columns[id]
    if cell.item and cell.row_mark and not deleted(buffer, cell.row_mark) then
      local mark =
        vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_COLUMN_NAMESPACE, id, { details = true })
      local text = vim.trim(
        table.concat(vim.api.nvim_buf_get_text(buffer.buf_nr, mark[1], mark[2], mark[3].end_row, mark[3].end_col, {}))
      )
      local editor = editable[cell.column]
      if text ~= cell.text and not editor then
        local item = cell.item.metadata
            and string.format("%s/%s", utils.resource_type(cell.item), cell.item.metadata.name)
          or cell.item.name
        table.insert(errors, string.format("%s of %s is not editable", cell.column, item))
      elseif text ~= cell.text then
        local edit, err = editor(buffer, cell.item, cell.text, text)
        if edit then
          table.insert(edits, edit)
        else
          table.insert(errors, err)
        end
      end
    end
  end
  return edits, errors
end

---Apply the edits and delete the resources, after confirming unless `force`.
---@param buffer KubeBuffer
---@param edits KubeEdit[]
---@param resources_to_delete table[]
---@param force boolean|nil
---@param callback fun(saved: boolean)
local function apply_changes(buffer, edits, resources_to_delete, force, callback)
  local kubectl = require("kubectl")
  local changes = vim.list_extend({}, edits)
  for _, resource in ipairs(resources_to_delete) do
    table.insert(changes, {
      title = "Delete " .. describe_target(resource),
      run = function(on_done, on_error)
        kubectl.delete(
          buffer.context,
          utils.resource_type(resource),
          resource.metadata.name,
          resource.metadata.namespace,
          on_done,
          on_error
        )
      end,
    })
  end

  local function run()
    local remaining = #changes
    -- Reload once all are done, failed or not, to show what the cluster is now
    local function finished()
      remaining = remaining - 1
      if remaining == 0 then
        callback(true)
      end
    end
    for _, change in ipairs(changes) do
      change.run(function(result)
        if result then
          vim.notify(vim.trim(result))
        end
        finished()
      end, function(err)
        vim.notify(string.format("Failed: %s\n%s", change.title, err), vim.log.levels.ERROR)
        finished()
      end)
    end
  end

  if force then
    run()
    return
  end
  local titles = vim.tbl_map(function(change)
    return "  " .. change.title
  end, changes)
  local prompt = string.format("Apply the changes (context: %s)?\n%s", buffer.context, table.concat(titles, "\n"))
  vim.schedule(function()
    require("kube.apply").confirm(prompt, function(confirmed)
      if confirmed then
        run()
      else
        callback(false)
      end
    end)
  end)
end

local function handle_buffer_save(buf_nr, callback, opts)
  callback = callback or function(saved) end
  opts = opts or {}

  local buffer = _G.kube_buffers[buf_nr]

  local edits, errors = cell_edits(buffer)
  if #errors > 0 then
    vim.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
    callback(false)
    return
  end

  local resources_to_delete = {}
  -- In the order of the rows
  local mark_ids = vim.tbl_keys(buffer.mark_mappings)
  table.sort(mark_ids)
  for _, mark_id in ipairs(mark_ids) do
    local marked_line = buffer.mark_mappings[mark_id]
    -- Rows that are not resources, like the containers of a pod, cannot be deleted
    if deleted(buffer, mark_id) and marked_line.item and marked_line.item.metadata then
      log.debug("mark to delete", mark_id, marked_line)
      table.insert(resources_to_delete, marked_line.item)
    end
  end
  log.debug("resources to delete", #resources_to_delete, "edits", #edits)

  if #edits == 0 and #resources_to_delete == 0 then
    callback(true)
    return
  end
  apply_changes(buffer, edits, resources_to_delete, opts.force, callback)
end

---@type EventHandler
local M = {
  on_buf_saved = handle_buffer_save,
}

return M
