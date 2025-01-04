local kubectl = require("kubectl")
local renderer = require("kube.renderer")

local M = {}

local formatters = {
	pods = require("kube.formatters.pods"),
	deployments = require("kube.formatters.deployments"),
	nodes = require("kube.formatters.nodes"),
	namespaces = require("kube.formatters.namespaces"),
	services = require("kube.formatters.services"),
	ingresses = require("kube.formatters.ingresses"),
	configmaps = require("kube.formatters.configmaps"),
	secrets = require("kube.formatters.secrets"),
}

function M.show_resources(resource_type, namespace)
	local formatter = formatters[resource_type]
	if not formatter then
		error("Unsupported resource type: " .. resource_type)
		return
	end

	local result = kubectl.get(resource_type, nil, namespace)
	local data = vim.fn.json_decode(result)

	local rows = formatter.format(data)
	renderer.render(formatter.headers, rows, resource_type, namespace)
end

return M
