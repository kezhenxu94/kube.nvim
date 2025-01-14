---@class Renderer
---@field load fun(buffer: KubeBuffer) Load content for the buffer

local renderers = {
  logs = require("kube.renderers.logs"),
  resources = require("kube.renderers.resources"),
  resource = require("kube.renderers.resource"),
  resource_yaml = require("kube.renderers.resource_yaml"),
}

---@type Renderer
local M = {
  load = function(buffer)
    local self = buffer
    local resource_kind = self.resource_kind
    local resource_name = self.resource_name
    local subresource_kind = self.subresource_kind
    local params = self.params or {}

    if resource_kind and not resource_name then
      renderers.resources.load(buffer)
      return
    end

    if resource_kind and resource_name and not subresource_kind then
      local output = params.output
      if not output then
        renderers.resource.load(buffer)
      elseif output == "yaml" then
        renderers.resource_yaml.load(buffer)
      else
        vim.notify("Unsupported output type: " .. output)
      end
      return
    end

    if subresource_kind and renderers[subresource_kind] then
      renderers[subresource_kind].load(buffer)
      return
    end

    if resource_kind and renderers[resource_kind] then
      renderers[resource_kind].load(buffer)
      return
    end

    renderers.resources.load(buffer)
  end,
}

return M
