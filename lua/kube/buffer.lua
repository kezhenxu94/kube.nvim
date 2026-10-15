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
---@field context string The kubectl context the buffer is bound to
---@field namespace string The namespace of the resource in buffer, "all" for cluster-scoped / all namespaces
---@field resource_kind string The kind of resource in buffer
---@field resource_name string|nil The name of the resource in buffer
---@field subresource_kind string|nil The kind of the subresource in buffer
---@field params table<string, any>|nil The parameters of the resource in buffer
---@field jobs table<number, vim.SystemObj> The jobs running in the buffer
---@field loading_job vim.SystemObj|nil The currently running loading job
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

  -- See `require("kube.utils").buf_name` for the format
  local buf_name = vim.api.nvim_buf_get_name(buf_nr)
  local path, query = buf_name:match("^kube://([^?]*)%??(.*)$")
  local segments = vim.split(path or "", "/", { plain = true, trimempty = true })
  log.debug("path", path, "query", query, "segments", segments)

  local context
  if segments[1] == "context" and #segments >= 3 then
    context = vim.uri_decode(segments[2])
    segments = vim.list_slice(segments, 3)
  end
  local namespace = "all"
  if segments[1] == "namespaces" and #segments >= 3 then
    namespace = segments[2]
    segments = vim.list_slice(segments, 3)
  end
  local resource_kind, resource_name, subresource_kind = segments[1], segments[2], segments[3]

  if not context or not resource_kind then
    error("Invalid buffer name format. Expected: kube://context/{context}/[namespaces/{namespace}/]{resource_kind}")
  end

  local params
  if query and query ~= "" then
    params = {}
    for param_str in query:gmatch("[^&]+") do
      local key, value = param_str:match("([^=]+)=?(.*)")
      if value == "" or value == "true" then
        value = true
      elseif value == "false" then
        value = false
      end
      params[key] = value
    end
  end

  local this = setmetatable({
    buf_nr = buf_nr,
    mark_mappings = {},
    mark_columns = {},
    context = context,
    namespace = namespace,
    resource_kind = resource_kind,
    resource_name = resource_name,
    subresource_kind = subresource_kind,
    params = params,
    jobs = {},
  }, KubeBuffer)
  _G.kube_buffers[buf_nr] = this

  this:setup()

  require("kube.keymaps").setup_buffer_keymaps(buf_nr)

  return this
end

function KubeBuffer:setup()
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })
end

function KubeBuffer:load()
  if self.loading_job and not self.loading_job:is_closing() then
    vim.notify("The buffer is currently being loaded", vim.log.levels.WARN)
    return
  end

  local parts = { self.namespace, self.resource_kind, self.resource_name, self.subresource_kind }
  vim.notify(string.format("Loading %s (context: %s)", table.concat(parts, "/"), self.context))
  self.loading_job = require("kube.renderers").load(self)
end

M.KubeBuffer = KubeBuffer

return M
