local kubectl = require("kubectl")
local log = require("kube.log")

---@type EventHandler
local M = {
  on_buf_saved = function(buf_nr, callback)
    callback = callback or function(_) end

    local buffer = _G.kube_buffers[buf_nr]
    if not vim.bo[buf_nr].modified then
      callback(false)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
    local temp_file = vim.fn.tempname()
    vim.fn.writefile(lines, temp_file)
    log.debug("applying resource", temp_file)

    kubectl.apply(buffer.context, buffer.namespace, temp_file, function(result)
      vim.fn.delete(temp_file)
      if result then
        vim.notify("Resource updated successfully")
      end
      callback(result ~= nil)
    end, function(data)
      vim.notify("Failed to update resource: " .. data, vim.log.levels.ERROR)
    end)
  end,
}

return M
