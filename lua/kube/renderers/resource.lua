local kubectl = require("kubectl")

---`kubectl describe` of the buffer's resource.
---@type Renderer
local M = {
  load = function(buffer)
    assert(buffer.resource_name, "resource_name is required")

    return kubectl.describe(
      buffer.context,
      buffer.resource_kind,
      buffer.resource_name,
      buffer.namespace,
      function(result)
        if result and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
          buffer:set_lines(vim.split(result, "\n"))
        end
      end,
      buffer:on_error()
    )
  end,
}

return M
