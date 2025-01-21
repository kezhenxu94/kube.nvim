---@diagnostic disable-next-line: unused-local
local Job = require("plenary.job")
local log = require("kube.log")
local M = {}

---@type table<number, KubeBuffer>
_G.kube_buffers = {}

---@class MarkedLine
---@field item table The raw data of the resource in buffer

---@class MarkedColumn
---@field item table The raw data of the resource in buffer
---@field column string The column name of the marked column

---@class KubeBuffer
---@field buf_nr number The buffer number
---@field header_row FormattedTableRow The header row of the buffer
---@field data table The raw data of the resource in buffer
---@field mark_mappings table<number, MarkedLine> Mapping of mark IDs to row data
---@field mark_columns table<number, MarkedColumn> Mapping of mark IDs to column field
---@field namespace string The namespace of the resource in buffer
---@field resource_kind string The kind of resource in buffer
---@field resource_name string|nil The name of the resource in buffer
---@field subresource_kind string|nil The kind of the subresource in buffer
---@field subresource_name string|nil The name of the subresource in buffer
---@field params table<string, any>|nil The parameters of the resource in buffer
---@field jobs table<number, Job> The jobs running in the buffer
---@field loading_job Job|nil The currently running loading job
local KubeBuffer = {}
KubeBuffer.__index = KubeBuffer

---Create a new KubeBuffer instance
---@param buf_nr number The buffer number
---@return KubeBuffer
function KubeBuffer:new(buf_nr)
  buf_nr = buf_nr or vim.api.nvim_get_current_buf()

  if _G.kube_buffers[buf_nr] then
    return _G.kube_buffers[buf_nr]
  end

  local buf_name = vim.api.nvim_buf_get_name(buf_nr)
  local namespace, resource_kind, resource_name, subresource_kind, subresource_name, remainders
  local path_params_pattern = "kube://([^?]+)??(.*)"
  local path, params = buf_name:match(path_params_pattern)
  log.debug("path", path, "params", params)

  local ns_pattern = "namespaces/([^/?]+)/([^/?]+)/?(.*)"

  namespace, resource_kind, remainders = path:match(ns_pattern)
  if not namespace then
    local cluster_pattern = "([^/?]+)/?(.*)"
    resource_kind, remainders = path:match(cluster_pattern)
    namespace = "all"
  end

  log.debug("namespace", namespace, "resource_kind", resource_kind, "remainders", remainders)

  if not resource_kind then
    error(
      "Invalid buffer name format. Expected: kube://namespaces/{namespace}/{resource_kind} or kube://{resource_kind}"
    )
  end

  if remainders then
    local resource_pattern = "([^/?]+)/?(.*)"
    resource_name, remainders = remainders:match(resource_pattern)
    log.debug("resource_name", resource_name, "remainders", remainders)

    if remainders then
      local subresource_pattern = "([^/?]+)/?(.*)"
      subresource_kind, remainders = remainders:match(subresource_pattern)
      log.debug("subresource_kind", subresource_kind, "remainders", remainders)

      if subresource_kind then
        local subresource_name_pattern = "([^/?]+)([/?])?(.*)"
        local rmd
        subresource_name, rmd = remainders:match(subresource_name_pattern)
        log.debug("subresource_name", subresource_name, "remainders", rmd)

        if rmd then
          remainders = rmd
        end
      end
    end
  end
  log.debug(
    "resource_kind",
    resource_kind,
    "resource_name",
    resource_name,
    "subresource_kind",
    subresource_kind,
    "subresource_name",
    subresource_name,
    "namespace",
    namespace,
    "remainders",
    remainders
  )

  if params then
    local param_table = {}
    for param_str in params:gmatch("[^&]+") do
      local key, value = param_str:match("([^=]+)=?(.*)")
      if value == "" then
        value = true
      elseif value == "true" then
        value = true
      elseif value == "false" then
        value = false
      end
      param_table[key] = value
    end
    params = param_table
  end

  local this = setmetatable({
    buf_nr = buf_nr,
    mark_mappings = {},
    mark_columns = {},
    namespace = namespace,
    resource_kind = resource_kind,
    resource_name = resource_name,
    subresource_kind = subresource_kind,
    subresource_name = subresource_name,
    params = params,
    jobs = {},
  }, KubeBuffer)
  _G.kube_buffers[buf_nr] = this

  self:setup()

  require("kube.keymaps").setup_buffer_keymaps(buf_nr)

  return this
end

function KubeBuffer:setup()
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })
end

function KubeBuffer:load()
  if self.loading_job then
    vim.notify("The buffer is currently being loaded", vim.log.levels.WARN)
    return
  end

  local parts = {}
  if self.namespace then
    table.insert(parts, self.namespace)
  end
  if self.resource_kind then
    table.insert(parts, self.resource_kind)
  end
  if self.resource_name then
    table.insert(parts, self.resource_name)
  end
  if self.subresource_kind then
    table.insert(parts, self.subresource_kind)
  end

  vim.notify(string.format("Loading %s", table.concat(parts, "/")))
  self.loading_job = require("kube.renderers").load(self)

  if self.loading_job then
    self.loading_job:after(function()
      self.loading_job = nil
    end)
  end
end

M.KubeBuffer = KubeBuffer

return M
