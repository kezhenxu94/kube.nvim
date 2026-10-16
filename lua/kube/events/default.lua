local constants = require("kube.constants")
local log = require("kube.log")
local utils = require("kube.utils")

---@param resource table
---@return string
local function describe_target(resource)
  return string.format("%s: %s/%s", utils.resource_type(resource), resource.metadata.namespace, resource.metadata.name)
end

---@param buffer KubeBuffer The buffer the resource belongs to
---@param resource table The resource to delete
---@param callback function The callback to call after deletion
local function delete_resource(buffer, resource, callback)
  local kubectl = require("kubectl")
  local resource_type = utils.resource_type(resource)
  kubectl.delete(buffer.context, resource_type, resource.metadata.name, resource.metadata.namespace, function(result)
    if result then
      vim.notify("Deleted " .. describe_target(resource))
    end
    callback(result)
  end, function(data)
    vim.notify(string.format("Failed to delete %s: \n%s", describe_target(resource), data), vim.log.levels.ERROR)
  end)
end

---@param buffer KubeBuffer
---@param row_mark integer
---@return boolean Whether the row was deleted
local function deleted(buffer, row_mark)
  local mark = vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_NAMESPACE, row_mark, { details = true })
  return #mark == 3 and mark[3] and mark[3].invalid == true
end

---The edits of the cells of editable columns, and the errors of the invalid ones.
---@param buffer KubeBuffer
---@return KubeEdit[] edits
---@return string[] errors
local function cell_edits(buffer)
  local edits, errors = {}, {}
  local editable = require("kube.renderers.resources").formatter_for(buffer).editable
  if not editable then
    return edits, errors
  end

  -- Marks are created in the order of the cells
  local ids = vim.tbl_keys(buffer.mark_columns)
  table.sort(ids)
  for _, id in ipairs(ids) do
    local cell = buffer.mark_columns[id]
    local editor = editable[cell.column]
    if editor and cell.item and cell.row_mark and not deleted(buffer, cell.row_mark) then
      local mark =
        vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_COLUMN_NAMESPACE, id, { details = true })
      local text = vim.trim(
        table.concat(vim.api.nvim_buf_get_text(buffer.buf_nr, mark[1], mark[2], mark[3].end_row, mark[3].end_col, {}))
      )
      if text ~= cell.text then
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
  for mark_id, marked_line in pairs(buffer.mark_mappings) do
    -- Rows that are not resources, like the containers of a pod, cannot be deleted
    if deleted(buffer, mark_id) and marked_line.item and marked_line.item.metadata then
      log.debug("mark to delete", mark_id, marked_line)
      table.insert(resources_to_delete, marked_line.item)
    end
  end
  log.debug("resources to delete", #resources_to_delete, "edits", #edits)

  if #edits > 0 then
    apply_changes(buffer, edits, resources_to_delete, opts.force, callback)
    return
  end

  if #resources_to_delete == 0 then
    callback(true)
    return
  end

  if #resources_to_delete == 1 then
    local resource = resources_to_delete[1]
    local msg = string.format("Delete %s (context: %s)?", describe_target(resource), buffer.context)
    vim.schedule(function()
      vim.ui.select({ "Yes", "No" }, {
        prompt = msg,
      }, function(choice)
        if choice == "Yes" then
          delete_resource(buffer, resource, function(result)
            if result then
              callback(true)
            end
          end)
        else
          callback(false)
        end
      end)
    end)
  else
    ---@type (table<string, any>|"cancel"|"all")[]
    local choices = { "cancel", "all" }
    for _, resource in ipairs(resources_to_delete) do
      table.insert(choices, resource)
    end

    local msg = string.format("Please select the resources to delete (context: %s):\n", buffer.context)

    vim.schedule(function()
      vim.ui.select(choices, {
        prompt = msg,
        format_item = function(item)
          if item == "all" then
            return "Delete all following resources"
          elseif item == "cancel" then
            return "Cancel"
          else
            return "Only delete " .. describe_target(item)
          end
        end,
      }, function(choice)
        log.debug("choice", choice)

        if choice == "all" then
          local remaining = #resources_to_delete
          for _, resource in ipairs(resources_to_delete) do
            delete_resource(buffer, resource, function()
              remaining = remaining - 1
              if remaining == 0 then
                vim.schedule(function()
                  vim.api.nvim_set_option_value("modified", false, { buf = buffer.buf_nr })
                end)
                callback(true)
              end
            end)
          end
        elseif choice == "cancel" then
          callback(false)
        elseif choice then
          assert(type(choice) == "table", "choice must be a table")
          delete_resource(buffer, choice, function(result)
            if result then
              callback(true)
            else
              callback(false)
            end
          end)
        end
      end)
    end)
  end
end

local function handle_buffer_delete(buf_nr, callback)
  callback = callback or function(_) end

  local buf = _G.kube_buffers[buf_nr]
  log.debug("shutting down jobs")

  if buf then
    local kubectl = require("kubectl")
    kubectl.kill(buf.loading_job)
    buf.loading_job = nil
    for pid, job in pairs(buf.jobs) do
      log.debug("shutting down job", pid)
      kubectl.kill(job)
      buf.jobs[pid] = nil
    end
  end

  _G.kube_buffers[buf_nr] = nil
  callback(true)
end

---@type EventHandler
local M = {
  on_buf_saved = handle_buffer_save,
  on_buf_deleted = handle_buffer_delete,
}

return M
