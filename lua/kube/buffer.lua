local constants = require("kube.constants")
local log = require("kube.log")
local M = {}

local GLOBAL_PORTFORWARDS = "portforwards"

---@type table<number, KubeBuffer>
_G.kube_buffers = {}

---@class MarkedLine
---@field item table The raw data of the resource in buffer
---@field line string The rendered line
---@field signature string The values of the row that a reload can change

---@class MarkedColumn
---@field item table The raw data of the resource in buffer
---@field column string The column name of the marked column
---@field text string The rendered value, to tell edits
---@field row_mark integer|nil The mark of the row in `mark_mappings`

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
---@field silent boolean|nil Whether the current load is a background refresh
---@field watch boolean|nil Whether the buffer reloads periodically, see `kube.refresh`
---@field flash_generation integer|nil The latest reload whose changed rows are highlighted
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

  -- The port forwards list spans all contexts
  if not resource_kind or (not context and resource_kind ~= GLOBAL_PORTFORWARDS) then
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
  -- After the keymaps, so mappings from the user's LspAttach take precedence
  require("kube.lsp").attach(buf_nr)

  return this
end

function KubeBuffer:setup()
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })
end

---@param opts {silent: boolean|nil}|nil `silent` for background refreshes: no loading status, no error notification
function KubeBuffer:load(opts)
  opts = opts or {}
  -- Operations reload their buffer when done, it may have been closed meanwhile
  if not vim.api.nvim_buf_is_valid(self.buf_nr) then
    return
  end
  if self.loading_job and not self.loading_job:is_closing() then
    if not opts.silent then
      vim.notify("The buffer is currently being loaded", vim.log.levels.WARN)
    end
    return
  end

  self.silent = opts.silent
  local empty = vim.api.nvim_buf_line_count(self.buf_nr) == 1
    and vim.api.nvim_buf_get_lines(self.buf_nr, 0, 1, false)[1] == ""
  if empty then
    self:set_status("Loading…", "Comment")
  end
  self.loading_job = require("kube.renderers").load(self)
end

---Show a status after the first line, nil to clear it.
---@param text string|nil
---@param hl string|nil
function KubeBuffer:set_status(text, hl)
  if not vim.api.nvim_buf_is_valid(self.buf_nr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_STATUS_NAMESPACE, 0, -1)
  if text then
    vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_STATUS_NAMESPACE, 0, 0, {
      virt_text = { { text, hl } },
      virt_text_pos = "eol",
    })
  end
end

---Error callback for kubectl calls loading this buffer.
---@return fun(err: string)
function KubeBuffer:on_error()
  return function(err)
    local message = vim.split(err ~= "" and err or "kubectl failed", "\n")[1]
    self:set_status("✗ " .. message, "ErrorMsg")
    if not self.silent then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
end

---Replace the buffer content with lines, keeping it unmodified.
---@param lines string[]
---@param modifiable boolean|nil
function KubeBuffer:set_lines(lines, modifiable)
  self:set_status(nil)
  vim.bo[self.buf_nr].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, lines)
  vim.bo[self.buf_nr].modifiable = modifiable == true
  vim.bo[self.buf_nr].modified = false
end

M.KubeBuffer = KubeBuffer

return M
