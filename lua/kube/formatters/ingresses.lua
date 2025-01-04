local utils = require("kube.utils")

---@class Formatter
local M = {}

M.headers = {
	"NAME",
	"CLASS",
	"HOSTS",
	"ADDRESS",
	"PORTS",
	"AGE",
}

function M.format(data)
	local rows = {}
	for _, item in ipairs(data.items) do
		local hosts = {}
		for _, rule in ipairs(item.spec.rules or {}) do
			table.insert(hosts, rule.host or "*")
		end

		local ports = {}
		for _, port in ipairs(item.spec.ports or {}) do
			table.insert(ports, string.format("%d/%s", port.port, port.protocol or "TCP"))
		end

		table.insert(rows, {
			row = {
				item.metadata.name,
				item.spec.ingressClassName or "<none>",
				table.concat(hosts, ","),
				item.status.loadBalancer
						and item.status.loadBalancer.ingress
						and item.status.loadBalancer.ingress[1].ip
					or "<pending>",
				table.concat(ports, ","),
				utils.calculate_age(item.metadata.creationTimestamp),
			},
			item = item,
		})
	end
	return rows
end

return M
