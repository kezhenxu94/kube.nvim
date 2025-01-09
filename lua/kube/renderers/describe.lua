local kubectl = require("kubectl")
local log = require("kube.log")

local M = {}

---@param buffer KubeBuffer The buffer to render into
function M.load(buffer)
  local self = buffer
  local resource_kind = self.resource_kind
  local resource_name = self.resource_name
  local namespace = self.namespace

  log.debug("loading describe buffer", resource_kind, resource_name, namespace)

  kubectl.describe(resource_kind, resource_name, namespace, function(result)
    vim.schedule(function()
      if not result then
        return
      end

      self:setup()

      vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
      vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, vim.split(result, "\n"))
      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
      vim.api.nvim_buf_set_option(self.buf_nr, "modified", false)
    end)
  end)
end

return M
