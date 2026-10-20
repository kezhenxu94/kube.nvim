local kubectl = require("kubectl")

---The decoded data of the buffer's secret, see `kube.secret`.
---@type Renderer
local M = {
  load = function(buffer)
    local job = kubectl.get(
      buffer.context,
      buffer.resource_kind,
      buffer.resource_name,
      buffer.namespace,
      nil,
      function(result)
        if not result or not vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
          return
        end
        local secret = vim.json.decode(result)
        buffer.data = secret
        vim.bo[buffer.buf_nr].filetype = "yaml"
        buffer:set_lines(require("kube.secret").to_lines(secret.data ~= vim.NIL and secret.data or nil), true)
      end,
      buffer:on_error()
    )
    if job then
      buffer.jobs[job.pid] = job
    end
    return job
  end,
}

return M
