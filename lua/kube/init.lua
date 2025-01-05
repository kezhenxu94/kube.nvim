local kubectl = require("kubectl")
local renderer = require("kube.renderer")

local M = {}

function M.show_resources(resource_kind, namespace)
	local formatter = require("kube.formatters")[resource_kind]
	kubectl.get(resource_kind, nil, namespace, function(result)
		vim.schedule(function()
			local data = vim.fn.json_decode(result)
			local rows = formatter.format(data)
			local buf_name = string.format("kube://%s/%s", namespace or "default", resource_kind)

			renderer.render(buf_name, formatter.headers, rows, resource_kind, namespace)
		end)
	end)
end

return M
