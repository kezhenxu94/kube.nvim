local kubectl = require("kubectl")

---The YAML of the buffer's resource, editable: `:w` applies it.
---@type Renderer
local M = {
  load = function(buffer)
    assert(buffer.resource_name, "resource_name is required")
    vim.bo[buffer.buf_nr].filetype = "yaml"

    local job = kubectl.get_resource_yaml(
      buffer.context,
      buffer.resource_kind,
      buffer.resource_name,
      buffer.namespace,
      function(yaml)
        if not vim.api.nvim_buf_is_valid(buffer.buf_nr) then
          return
        end
        if yaml then
          buffer:set_lines(vim.split(yaml, "\n"), true)
        elseif vim.api.nvim_buf_line_count(buffer.buf_nr) == 1 then
          -- Nothing loaded: nothing to edit and apply
          vim.bo[buffer.buf_nr].modifiable = false
        end
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
