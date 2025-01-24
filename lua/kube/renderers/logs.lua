---@diagnostic disable-next-line: unused-local
local Job = require("plenary.job")
local constants = require("kube.constants")
local kubectl = require("kubectl")
local log = require("kube.log")

---@type Renderer
local M = {

  ---@param buffer KubeBuffer The buffer to render into
  load = function(buffer)
    local self = buffer
    local resource_kind = self.resource_kind
    local resource_name = self.resource_name
    local subresource_kind = self.subresource_kind
    local subresource_name = self.subresource_name
    local namespace = self.namespace
    local params = self.params or {}

    log.debug("loading log buffer", resource_kind, resource_name, namespace, subresource_kind, subresource_name, params)

    local follow = params.follow
    local container = params.container

    local job = kubectl.logs(resource_kind, resource_name, container, namespace, follow, function(result)
      vim.schedule(function()
        if not result then
          return
        end

        self:setup()

        vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
        local lines = vim.split(result, "\n")
        local start = vim.api.nvim_buf_line_count(self.buf_nr)
        vim.api.nvim_buf_set_lines(self.buf_nr, follow and math.max(0, start - 1) or -1, -1, false, lines)

        if follow then
          vim.api.nvim_buf_set_lines(self.buf_nr, -1, -1, false, { "" })
          vim.api.nvim_buf_set_extmark(
            self.buf_nr,
            constants.KUBE_NAMESPACE,
            vim.api.nvim_buf_line_count(self.buf_nr) - 1,
            0,
            {
              virt_text = { { "Waiting for new logs... (Ctrl+C to stop)", "Comment" } },
              virt_text_pos = "overlay",
            }
          )
        end

        vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
        vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
      end)
    end)

    if job then
      self.jobs[job.pid] = job
      log.debug("job", job.pid, "started")

      if follow then
        vim.keymap.set("n", "<C-c>", function()
          if self.jobs[job.pid] then
            log.debug("killing job", job.pid)
            vim.loop.kill(job.pid, 15)
            self.jobs[job.pid] = nil

            vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
            vim.api.nvim_buf_set_extmark(
              self.buf_nr,
              constants.KUBE_NAMESPACE,
              vim.api.nvim_buf_line_count(self.buf_nr) - 1,
              0,
              {
                virt_text = { { "Stopped following logs, to restart, re-edit this buffer with `:e`", "Comment" } },
                virt_text_pos = "overlay",
              }
            )
            vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
            vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
          end
        end, { buffer = self.buf_nr, desc = "Stop kubectl logs job" })
      end
      return job
    end
    return nil
  end,
}

return M
