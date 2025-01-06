---@class Renderer
---@field render fun(buf_nr: number, data: table): (number, table) Function to render the data into the buffer

local renderers = {
	logs = require("kube.renderers.logs"),
}

---@type Renderer
local M = {}

function M.load(buffer)
	local renderer = renderers[buffer.resource_kind]
	if renderer then
		renderer.load(buffer)
	else
		require("kube.renderers.default").load(buffer)
	end
end

return M