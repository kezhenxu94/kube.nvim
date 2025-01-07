local KubeBuffer = require("kube.buffer").KubeBuffer

local show_yaml = function(resource)
	local kind = resource.kind
	local name = resource.metadata.name
	local namespace = resource.metadata.namespace

	local buf_name = string.format("kube://%s/%s/%s.yaml", namespace, string.lower(kind), name)
	local buf_nr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf_nr, buf_name)

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf_nr })
	vim.api.nvim_set_option_value("filetype", "yaml", { buf = buf_nr })

	vim.api.nvim_set_current_buf(buf_nr)

	local job = require("kubectl").get_resource_yaml(kind, name, namespace, function(yaml)
		vim.schedule(function()
			if yaml then
				vim.api.nvim_buf_set_lines(buf_nr, 0, -1, false, vim.split(yaml, "\n"))
			else
				vim.api.nvim_buf_set_lines(buf_nr, 0, -1, false, { "Failed to get resource YAML" })
			end

			vim.api.nvim_set_option_value("modifiable", false, { buf = buf_nr })
		end)
	end)

	if job then
		local buf = KubeBuffer:new(buf_nr)
		buf.jobs[job.pid] = job
	end
end

---@type Actions
local M = {
	drill_down_resource = show_yaml,
	show_yaml = show_yaml,

	---@diagnostic disable-next-line: unused-local
	show_logs = function(resource, follow, parent)
		local kind = resource.kind

		vim.notify(string.format("%s resources do not support logs", kind), vim.log.levels.WARN)
	end,
}

return M
