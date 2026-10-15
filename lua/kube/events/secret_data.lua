local apply = require("kube.apply")
local secret = require("kube.secret")

---@type EventHandler
local M = {
  on_buf_saved = function(buf_nr, callback, opts)
    callback = callback or function(_) end
    opts = opts or {}

    local buffer = _G.kube_buffers[buf_nr]
    local new, err = secret.from_lines(vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false))
    if not new then
      vim.notify("Invalid secret data, " .. err, vim.log.levels.ERROR)
      callback(false)
      return
    end

    local old = buffer.data and buffer.data.data
    local patch, changes = secret.patch(old ~= vim.NIL and old or {}, new)
    if not patch then
      vim.notify("No changes to apply")
      callback(true)
      return
    end

    local function update()
      require("kubectl").patch(buffer.context, "secret", buffer.resource_name, buffer.namespace, patch, function(result)
        if result then
          vim.notify(vim.trim(result))
        end
        callback(result ~= nil)
      end, function(patch_err)
        vim.notify("Failed to update secret: " .. patch_err, vim.log.levels.ERROR)
      end)
    end

    if opts.force then
      update()
      return
    end

    local summary = {}
    for _, change in ipairs({ "added", "changed", "removed" }) do
      if #changes[change] > 0 then
        table.insert(summary, string.format("%s %s", change, table.concat(changes[change], ", ")))
      end
    end
    local title = string.format(
      "Update secret %s/%s (context: %s): %s?",
      buffer.namespace,
      buffer.resource_name,
      buffer.context,
      table.concat(summary, "; ")
    )
    apply.confirm(title, function(confirmed)
      if confirmed then
        update()
      else
        callback(false)
      end
    end)
  end,
}

return M
