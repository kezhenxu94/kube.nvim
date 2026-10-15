local kubectl = require("kubectl")

---`kubectl rollout history` of the buffer's workload.
---@type Renderer
local M = {
  load = function(buffer)
    return kubectl.rollout(
      buffer.context,
      "history",
      buffer.resource_kind,
      buffer.resource_name,
      buffer.namespace,
      function(result)
        if result and vim.api.nvim_buf_is_valid(buffer.buf_nr) then
          buffer:set_lines(vim.split(vim.trim(result), "\n"))
        end
      end,
      buffer:on_error()
    )
  end,
}

return M
