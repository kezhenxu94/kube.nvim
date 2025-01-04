local kubectl = require("kubectl")
local renderer = require("kube.renderer")

local M = {}

function M.show_resources(resource_kind, namespace)
	local formatter = require("kube.formatters")[resource_kind]
	local result = kubectl.get(resource_kind, nil, namespace)
	local data = vim.fn.json_decode(result)

	local rows = formatter.format(data)
	renderer.render(formatter.headers, rows, resource_kind, namespace)
end

return M
