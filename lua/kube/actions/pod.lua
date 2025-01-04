local renderer = require("kube.renderer")

---@type Actions
local M = {
	drill_down_resource = function(resource)
		local namespace = resource.metadata.namespace
		local formatter = require("kube.formatters")["containers"]
		local rows = formatter.format(resource)
		renderer.render(formatter.headers, rows, "containers", namespace)
	end,
}

return M
