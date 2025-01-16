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
  local params = self.params or {}

  log.debug("rendering yaml buffer", resource_kind, resource_name, namespace)

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
  vim.api.nvim_set_option_value("filetype", "yaml", { buf = self.buf_nr })

  assert(resource_name, "resource_name is required")

  local job = require("kubectl").get_resource_yaml(resource_kind, resource_name, namespace, function(yaml)
    vim.schedule(function()
      if yaml then
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, vim.split(yaml, "\n"))
      else
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, { "Failed to get resource YAML" })
      end

      vim.api.nvim_set_option_value("modifiable", params.edit == true, { buf = self.buf_nr })
      vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    end)
  end)

  if job then
    local buf = KubeBuffer:new(self.buf_nr)
    buf.jobs[job.pid] = job
  end

  if params.edit then
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = self.buf_nr,
      callback = function()
        if vim.api.nvim_get_option_value("modified", { buf = self.buf_nr }) then
          local lines = vim.api.nvim_buf_get_lines(self.buf_nr, 0, -1, false)
          local temp_file = vim.fn.tempname()
          vim.fn.writefile(lines, temp_file)
          log.debug("applying resource", temp_file)

          kubectl.apply(namespace, temp_file, function(result)
            vim.schedule(function()
              if result then
                vim.notify("Resource updated successfully")
                vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
              else
                vim.notify("Failed to update resource", vim.log.levels.ERROR)
              end
              vim.fn.delete(temp_file)
            end)
          end, function(data)
            vim.schedule(function()
              vim.notify("Failed to update resource: " .. data, vim.log.levels.ERROR)
            end)
          end)
        end
      end,
    })
  end

  return job
end

return M
