local log = require("kube.log")

---@type Actions
local M = {
	drill_down_resource = function(resource, parent)
		log.debug("drilling down to container", resource)

		if not parent then
			log.error("parent resource is required")
			return
		end
		if not parent.name then
			log.error("parent resource name is required")
			return
		end

		local buf = vim.api.nvim_create_buf(false, true)
		local buf_name =
			string.format("kube://namespaces/%s/%s/%s/exec", parent.namespace or "default", parent.name, resource.name)
		vim.api.nvim_buf_set_name(buf, buf_name)

		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "terminal", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

		vim.api.nvim_set_current_buf(buf)

		local cmd = string.format(
			"kubectl exec -it -n %s %s -c %s -- bash || sh",
			parent.namespace or "default",
			parent.name,
			resource.name
		)
		vim.fn.termopen(cmd)
		vim.opt_local.number = false
		vim.opt_local.relativenumber = false
		vim.cmd("file " .. buf_name)
		vim.cmd("startinsert")
	end,
}

return M
