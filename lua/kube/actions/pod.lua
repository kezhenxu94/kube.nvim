local log = require("kube.log")

---@type Actions
local M = {
	drill_down_resource = function(resource)
		log.debug("drilling down to pod", resource)

		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace
		local buf_name
		if namespace then
			buf_name = string.format("kube://namespaces/%s/%s/%s/containers", namespace, kind, name)
		else
			buf_name = string.format("kube://%s/%s/containers", kind, name)
		end

		vim.cmd.edit(buf_name)
	end,
}

return M
