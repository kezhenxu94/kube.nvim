local constants = require("kube.constants")
local log = require("kube.log")

---@param resource table The resource to delete
---@param callback function The callback to call after deletion
local function delete_resource(resource, callback)
  local kubectl = require("kubectl")
  kubectl.delete(resource.kind, resource.metadata.name, resource.metadata.namespace, function(result)
    if result then
      vim.schedule(function()
        vim.notify(
          string.format("Deleted %s: %s/%s", resource.kind, resource.metadata.namespace, resource.metadata.name)
        )
      end)
    end
    callback(result)
  end, function(data)
    vim.schedule(function()
      vim.notify(
        string.format(
          "Failed to delete %s: %s/%s: \n%s",
          resource.kind,
          resource.metadata.namespace,
          resource.metadata.name,
          data
        )
      )
    end)
  end)
end

local function handle_buffer_save(buf_nr)
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
    return
  end

  if #resources_to_delete == 1 then
    local resource = resources_to_delete[1]
    local msg = string.format("Delete %s: %s/%s?", resource.kind, resource.metadata.namespace, resource.metadata.name)
    vim.schedule(function()
      vim.ui.select({ "Yes", "No" }, {
        prompt = msg,
      }, function(choice)
        if choice == "Yes" then
          delete_resource(resource, function(result)
            if result then
              buffer:load()
            end
          end)
        else
          vim.notify("Deletion cancelled")
        end
      end)
    end)
  else
    local choices = { "cancel", "all" }
    for _, resource in ipairs(resources_to_delete) do
      table.insert(choices, resource)
    end

    local msg = "Please select the resources to delete:\n"

    vim.schedule(function()
      vim.ui.select(choices, {
        prompt = msg,
        format_item = function(item)
          if item == "all" then
            return "Delete all following resources"
          elseif item == "cancel" then
            return "Cancel"
          else
            return string.format("Only delete %s: %s/%s", item.kind, item.metadata.namespace, item.metadata.name)
          end
        end,
      }, function(choice)
        log.debug("choice", choice)

        if choice == "all" then
          local remaining = #resources_to_delete
          for _, resource in ipairs(resources_to_delete) do
            delete_resource(resource, function()
              remaining = remaining - 1
              if remaining == 0 then
                vim.schedule(function()
                  vim.api.nvim_set_option_value("modified", false, { buf = buffer.buf_nr })
                  buffer:load()
                end)
              end
            end)
          end
        elseif choice == "cancel" then
          vim.notify("Deletion cancelled")
        elseif choice then
          delete_resource(choice, function(result)
            if result then
              buffer:load()
            end
          end)
        end
      end)
    end)
  end
end

local function handle_buffer_delete(buf_nr)
  local buf = _G.kube_buffers[buf_nr]
  log.debug("shutting down jobs")

  if buf then
    for job_id, _ in pairs(buf.jobs) do
      log.debug("shutting down job", job_id)
      vim.loop.kill(job_id, vim.loop.constants.SIGTERM)
      buf.jobs[job_id] = nil
    end
  end

  _G.kube_buffers[buf_nr] = nil
end

---@type EventHandler
local M = {
  on_buf_saved = handle_buffer_save,
  on_buf_deleted = handle_buffer_delete,
}

return M
