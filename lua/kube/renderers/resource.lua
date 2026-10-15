local kubectl = require("kubectl")
local log = require("kube.log")

---@type Renderer
local M = {
  ---@param buffer KubeBuffer The buffer to render into
  load = function(buffer)
    local self = buffer
    local resource_kind = self.resource_kind
    local resource_name = self.resource_name
    local namespace = self.namespace

    assert(resource_name, "resource_name is required")

    log.debug("loading describe buffer", resource_kind, resource_name, namespace)

    return kubectl.describe(self.context, resource_kind, resource_name, namespace, function(result)
      if not result or not vim.api.nvim_buf_is_valid(self.buf_nr) then
        return
      end

      self:setup()

      vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
      vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, vim.split(result, "\n"))
      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
      vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    end)
  end,
}
return M
