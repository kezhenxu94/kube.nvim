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

local function handle_buffer_save(buf_nr, callback)
  callback = callback or function(saved) end

  local buffer = _G.kube_buffers[buf_nr]
  local marks_to_delete = {}

  for mark_id, marked_line in pairs(buffer.mark_mappings) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_NAMESPACE, mark_id, { details = true })
    if #mark == 3 and mark[3] and mark[3].invalid then
      log.debug("mark to delete", mark_id, marked_line)
      table.insert(marks_to_delete, mark_id)
    end
  end
  log.debug("marks to delete", #marks_to_delete, "buffer marks", #buffer.mark_mappings)

  local resources_to_delete = {}
  for _, mark_id in ipairs(marks_to_delete) do
    local resource = buffer.mark_mappings[mark_id].item
    if resource then
      table.insert(resources_to_delete, resource)
    end
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
