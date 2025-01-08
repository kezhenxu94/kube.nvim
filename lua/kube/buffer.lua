---@class MarkedLine
---@field item table The raw data of the resource in buffer

local constants = require("kube.constants")
local log = require("kube.log")
local M = {}

---@type table<number, KubeBuffer>
_G.kube_buffers = {}

---@class KubeBuffer
---@field buf_nr number The buffer number
---@field data table The raw data of the resource in buffer
---@field mark_mappings table<number, MarkedLine> Mapping of mark IDs to row data
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
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = self.buf_nr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = vim.api.nvim_create_augroup("kube_buffer_save", { clear = true }),
    buffer = self.buf_nr,
    callback = function()
      self:handle_buffer_save()
    end,
  })
end

function KubeBuffer:load()
  require("kube.renderers").load(self)
end

---@param buffer KubeBuffer The buffer being saved
function KubeBuffer:handle_buffer_save()
  local buffer = self
  local marks_to_delete = {}

  for mark_id, marked_line in pairs(self.mark_mappings) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(buffer.buf_nr, constants.KUBE_NAMESPACE, mark_id, { details = true })
    if #mark == 3 and mark[3] and mark[3].invalid then
      log.debug("mark to delete", mark_id, marked_line)
      table.insert(marks_to_delete, mark_id)
    end
  end
  log.debug("marks to delete", #marks_to_delete, "buffer marks", #buffer.mark_mappings)

  local resources_to_delete = {}
  for _, mark_id in ipairs(marks_to_delete) do
    local resource = buffer.mark_mappings[mark_id].item
    if resource then
      table.insert(resources_to_delete, resource)
    end
  end

  if #resources_to_delete == 0 then
    return
  end

  if #resources_to_delete == 1 then
    local resource = resources_to_delete[1]
    local msg = string.format("Delete %s: %s/%s?", resource.kind, resource.metadata.namespace, resource.metadata.name)
    vim.ui.select({ "Yes", "No" }, {
      prompt = msg,
    }, function(choice)
      if choice == "Yes" then
        self:delete_resource(resource, function(result)
          if result then
            self:load()
          end
        end)
      else
        vim.notify("Deletion cancelled")
      end
    end)
  else
    local choices = { "all", "cancel" }
    for _, resource in ipairs(resources_to_delete) do
      table.insert(choices, resource)
    end

    local msg = "Please select the resources to delete:\n"

    vim.ui.select(choices, {
      prompt = msg,
      format_item = function(item)
        if item == "all" then
          return "Delete all following resources"
        elseif item == "cancel" then
          return "Cancel"
        else
          return string.format("Only delete %s: %s/%s", item.kind, item.metadata.namespace, item.metadata.name)
        end
      end,
    }, function(choice)
      log.debug("choice", choice)

      if choice == "all" then
        local kubectl = require("kubectl")
        local remaining = #resources_to_delete
        for _, resource in ipairs(resources_to_delete) do
          self:delete_resource(resource, function(result)
            remaining = remaining - 1
            if remaining == 0 then
              vim.schedule(function()
                vim.api.nvim_buf_set_option(buffer.buf_nr, "modified", false)
                self:load()
              end)
            end
          end)
        end
      elseif choice == "cancel" then
        vim.notify("Deletion cancelled")
      elseif choice then
        self:delete_resource(choice, function(result)
          if result then
            self:load()
          end
        end)
      end
    end)
  end
end

---@param resource table The resource to delete
---@param callback function The callback to call after deletion
function KubeBuffer:delete_resource(resource, callback)
  local kubectl = require("kubectl")
  kubectl.delete(resource.kind, resource.metadata.name, resource.metadata.namespace, function(result)
    if result then
      vim.schedule(function()
        vim.notify(
          string.format("Deleted %s: %s/%s", resource.kind, resource.metadata.namespace, resource.metadata.name)
        )
      end)
    end
    callback(result)
  end, function(data)
    vim.schedule(function()
      vim.notify(
        string.format(
          "Failed to delete %s: %s/%s: %s",
          resource.kind,
          resource.metadata.namespace,
          resource.metadata.name,
          data
        )
      )
    end)
  end)
end

M.KubeBuffer = KubeBuffer

return M
