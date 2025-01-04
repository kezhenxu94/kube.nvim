local kubectl = require("kubectl")
local renderer = require("kube.renderer")

local M = {}

function M.show_resources(resource_type, namespace)
	local formatter = require("kube.formatters")[resource_type]
	local result = kubectl.get(resource_type, nil, namespace)
	local data = vim.fn.json_decode(result)

	local rows = formatter.format(data)
	renderer.render(formatter.headers, rows, resource_type, namespace)
end

return M
