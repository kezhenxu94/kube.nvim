local renderer = require("kube.renderer")

---@type Actions
local M = {
	drill_down_resource = function(resource)
		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace
		local formatter = require("kube.formatters")["containers"]
		local rows = formatter.format(resource)
		local buf_name = string.format("kube://%s/%s/%s/containers", namespace or "default", kind, name)
		renderer.render(buf_name, formatter.headers, rows, "containers", namespace)
	end,
}

return M
