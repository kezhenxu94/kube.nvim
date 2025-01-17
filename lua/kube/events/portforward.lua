local constants = require("kube.constants")
local log = require("kube.log")
local M = {
  on_buf_saved = function(buf_nr)
    local buffer = _G.kube_buffers[buf_nr]
    local marks_to_delete = {}

    for mark_id, marked_line in pairs(buffer.mark_mappings) do
      local mark =
        vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_NAMESPACE, mark_id, { details = true })
      if #mark == 3 and mark[3] and mark[3].invalid then
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

    log.debug("resources to delete", resources_to_delete)

    if #resources_to_delete == 1 then
      local portforward = resources_to_delete[1]
      local msg = string.format("Delete port forward: %s/%s?", portforward.id, portforward.local_port)
      vim.schedule(function()
        vim.ui.select({ "Yes", "No" }, {
          prompt = msg,
        }, function(choice)
          if choice == "Yes" then
            vim.loop.kill(portforward.portforward.pid, vim.loop.constants.SIGTERM)
            _G.portforwards[portforward.id] = nil
            buffer:load()
          end
        end)
      end)
    else
      local choices = { "cancel", "all" }
      for _, portforward in ipairs(resources_to_delete) do
        table.insert(choices, portforward)
      end

      local msg = "Please select the port forwards to delete:\n"
      vim.schedule(function()
        vim.ui.select(choices, {
          prompt = msg,
          format_item = function(item)
            if item == "cancel" then
              return "Cancel"
            elseif item == "all" then
              return "Delete all following port forwards"
            else
              return string.format("Delete port forward: %s/%s", item.id, item.local_port)
            end
          end,
        }, function(choice)
          if choice == "all" then
            for _, portforward in ipairs(resources_to_delete) do
              vim.loop.kill(portforward.portforward.pid, vim.loop.constants.SIGTERM)
              _G.portforwards[portforward.id][portforward.local_port] = nil
            end
            buffer:load()
          elseif choice == "cancel" then
            vim.notify("Deletion cancelled")
          elseif choice then
            vim.loop.kill(choice.portforward.pid, vim.loop.constants.SIGTERM)
            _G.portforwards[choice.id] = nil
            buffer:load()
          end
        end)
      end)
    end
  end,
}

return M
