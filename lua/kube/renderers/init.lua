---@class Renderer
---@field render fun(buf_nr: number, data: table): (number, table) Function to render the data into the buffer

local renderers = {
	logs = require("kube.renderers.logs"),
}

---@type Renderer
local M = {}

function M.load(buffer)
	local self = buffer
	local resource_kind = self.resource_kind
	local resource_name = self.resource_name
	local subresource_kind = self.subresource_kind
	local namespace = self.namespace

	local renderer = require("kube.renderers.default")
	if resource_kind and renderers[resource_kind] then
		renderer = renderers[resource_kind]
	end
	if subresource_kind and renderers[subresource_kind] then
		renderer = renderers[subresource_kind]
	end

	renderer.load(buffer)
end

return M