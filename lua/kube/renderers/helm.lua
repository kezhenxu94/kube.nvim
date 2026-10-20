local formatters = require("kube.formatters")
local helm = require("helm")

---Views of a release that are text, by subresource: nil is `helm status`.
local TEXT = {
  values = { filetype = "yaml" },
  manifest = { filetype = "yaml" },
  notes = {},
}

---@param buffer KubeBuffer
---@param job vim.SystemObj|nil
---@return vim.SystemObj|nil
local function track(buffer, job)
  if job then
    buffer.jobs[job.pid] = job
  end
  return job
end

---@param buffer KubeBuffer
---@param formatter Formatter
---@return fun(result: string|nil)
local function render_json(buffer, formatter)
  return function(result)
    if result and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      -- helm outputs `null` rather than `[]` when there is nothing
      local data = vim.json.decode(result)
      require("kube.renderers.resources").render(buffer, formatter, data ~= vim.NIL and data or {})
    end
  end
end

---Helm releases and their views: `helm-releases[/{name}[/values|manifest|notes|history]]`.
---@type Renderer
local M = {
  load = function(buffer)
    local params = buffer.params or {}
    local context, name, namespace = buffer.context, buffer.resource_name, buffer.namespace

    if not name then
      return track(
        buffer,
        helm.list(context, namespace, render_json(buffer, formatters["helm-releases"]), buffer:on_error())
      )
    end
    if buffer.subresource_kind == "history" then
      return track(
        buffer,
        helm.history(context, name, namespace, render_json(buffer, formatters["helm-history"]), buffer:on_error())
      )
    end

    local text = buffer.subresource_kind and TEXT[buffer.subresource_kind]
    if buffer.subresource_kind and not text then
      vim.notify("Unsupported helm release view: " .. buffer.subresource_kind, vim.log.levels.ERROR)
      return nil
    end
    local function show(result)
      if result and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
        if text and text.filetype then
          vim.bo[buffer.buf_nr].filetype = text.filetype
        end
        buffer:set_lines(vim.split(vim.trim(result), "\n"))
      end
    end
    if not text then
      return track(buffer, helm.status(context, name, namespace, show, buffer:on_error()))
    end
    return track(
      buffer,
      helm.get(
        context,
        buffer.subresource_kind,
        name,
        namespace,
        { all = params.all == true, revision = params.revision },
        show,
        buffer:on_error()
      )
    )
  end,
}

return M
