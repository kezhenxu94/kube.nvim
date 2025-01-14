local kubectl = require("kubectl")
local log = require("kube.log")
local KubeBuffer = require("kube.buffer").KubeBuffer

local M = {}

---@param buffer KubeBuffer The buffer to render into
function M.load(buffer)
  local self = buffer
  local resource_kind = self.resource_kind
  local resource_name = self.resource_name
  local namespace = self.namespace

  log.debug("rendering yaml buffer", resource_kind, resource_name, namespace)

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
  vim.api.nvim_set_option_value("filetype", "yaml", { buf = self.buf_nr })

  vim.api.nvim_set_current_buf(self.buf_nr)

  local job = require("kubectl").get_resource_yaml(resource_kind, resource_name, namespace, function(yaml)
    vim.schedule(function()
      if yaml then
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, vim.split(yaml, "\n"))
      else
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, { "Failed to get resource YAML" })
      end

      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
      vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    end)
  end)

  if job then
    local buf = KubeBuffer:new(self.buf_nr)
    buf.jobs[job.pid] = job
  end

  return job
end

return M 