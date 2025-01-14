---@class Renderer
---@field load fun(buffer: KubeBuffer) Load content for the buffer

local renderers = {
  logs = require("kube.renderers.logs"),
  describe = require("kube.renderers.describe"),
  default = require("kube.renderers.default"),
  yaml = require("kube.renderers.yaml"),
}

---@type Renderer
local M = {
  load = function(buffer)
    local self = buffer
    local resource_kind = self.resource_kind
    local resource_name = self.resource_name
    local subresource_kind = self.subresource_kind

    if subresource_kind and renderers[subresource_kind] then
      renderers[subresource_kind].load(buffer)
      return
    end

    if resource_kind and resource_name and not subresource_kind then
      renderers.describe.load(buffer)
      return
    end

    if resource_kind and renderers[resource_kind] then
      renderers[resource_kind].load(buffer)
      return
    end

    renderers.default.load(buffer)
  end,
}

return M
