local apply = require("kube.apply")

---@type EventHandler
local M = {
  on_buf_saved = function(buf_nr, callback, opts)
    callback = callback or function(_) end
    opts = opts or {}

    local buffer = _G.kube_buffers[buf_nr]
    if not vim.bo[buf_nr].modified then
      callback(false)
      return
    end

    apply.with_temp_file(vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false), function(file, cleanup)
      apply.apply(buffer.context, buffer.namespace, file, {
        force = opts.force,
        title = string.format("Apply %s/%s (context: %s)?", buffer.resource_kind, buffer.resource_name, buffer.context),
      }, function(applied)
        cleanup()
        callback(applied)
      end)
    end)
  end,
}

return M
