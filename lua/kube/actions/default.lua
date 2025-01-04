---@type Actions
local M = {
	drill_down_resource = function(resource)
		local kind = resource.kind
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace

		local buf_name = string.format("kube://%s/%s/%s.yaml", namespace, string.lower(kind), name)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, buf_name)

		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "yaml", { buf = buf })

		vim.api.nvim_set_current_buf(buf)

		local yaml = require("kubectl").get_resource_yaml(kind, name, namespace)
		if yaml then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(yaml, "\n"))
		else
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Failed to get resource YAML" })
		end

		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end,
}

return M
