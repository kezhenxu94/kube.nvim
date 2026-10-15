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
    local namespace = self.namespace
    local params = self.params or {}

    log.debug("loading log buffer", resource_kind, resource_name, namespace, subresource_kind, params)

    local follow = params.follow
    local container = params.container
    ---@type integer|nil
    local status_mark

    ---@param text string
    local function set_status(text)
      status_mark = vim.api.nvim_buf_set_extmark(
        self.buf_nr,
        constants.KUBE_NAMESPACE,
        vim.api.nvim_buf_line_count(self.buf_nr) - 1,
        0,
        { id = status_mark, virt_text = { { text, "Comment" } }, virt_text_pos = "overlay" }
      )
    end

    local job = kubectl.logs(self.context, resource_kind, resource_name, container, namespace, follow, function(result)
      if not vim.api.nvim_buf_is_valid(self.buf_nr) then
        return
      end

      self:setup()

      vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
      local lines = vim.split(result, "\n")
      if follow then
        -- Replace the trailing placeholder line, then add a new one for the status
        local start = vim.api.nvim_buf_line_count(self.buf_nr)
        vim.api.nvim_buf_set_lines(self.buf_nr, start - 1, -1, false, lines)
        vim.api.nvim_buf_set_lines(self.buf_nr, -1, -1, false, { "" })
        set_status("Waiting for new logs... (Ctrl+C to stop)")
      else
        vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, lines)
      end

      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
      vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    end)

    if not job then
      return nil
    end

    self.jobs[job.pid] = job
    log.debug("job", job.pid, "started")

    if follow then
      vim.keymap.set("n", "<C-c>", function()
        if self.jobs[job.pid] then
          log.debug("killing job", job.pid)
          kubectl.kill(job)
          self.jobs[job.pid] = nil
          set_status("Stopped following logs, to restart, re-edit this buffer with `:e`")
        end
      end, { buffer = self.buf_nr, desc = "Stop kubectl logs job" })
    end
    return job
  end,
}

return M
