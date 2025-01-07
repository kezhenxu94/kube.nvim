local log = require("kube.log")

local M = {}

local highlights = {
  KubePending = { fg = "#fe640b" },
  KubeRunning = { fg = "#40a02b" },
  KubeFailed = { fg = "#d20f39" },
  KubeSucceeded = { fg = "#9ca0b0" },
  KubeUnknown = { fg = "#6c6f85" },
  KubeHeader = { fg = "#df8e1d", bold = true, underline = true },
}

---@type table<number, KubeBuffer>
_G.kube_buffers = {}

---@class KubeBuffer
---@field buf_nr number The buffer number
---@field mark_mappings table<number, table> Mapping of mark IDs to row data
---@field namespace string The namespace of the resource in buffer
---@field resource_kind string The kind of resource in buffer
---@field resource_name string|nil The name of the resource in buffer
---@field subresource_kind string|nil The kind of the subresource in buffer
---@field subresource_name string|nil The name of the subresource in buffer
---@field params string|nil The parameters of the resource in buffer
---@field jobs table<number, Job> The jobs running in the buffer
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
  local namespace, resource_kind, resource_name, subresource_kind, subresource_name, remainders, params
  local ns_pattern = "kube://namespaces/([^/?]+)/([^/?]+)/?(.*)"

  namespace, resource_kind, remainders = buf_name:match(ns_pattern)
  if not namespace then
    local cluster_pattern = "kube://([^/?]+)/?(.*)"
    resource_kind, remainders = buf_name:match(cluster_pattern)
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

  if remainders then
    local params_pattern = "([^/?]+)/?(.*)"
    params, remainders = remainders:match(params_pattern)
    log.debug("params", params, "remainders", remainders)

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
  end

  local this = setmetatable({
    buf_nr = buf_nr,
    mark_mappings = {},
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
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })

  for group, colors in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, colors)
  end
end

function KubeBuffer:load()
  require("kube.renderers").load(self)
end

M.KubeBuffer = KubeBuffer

return M
