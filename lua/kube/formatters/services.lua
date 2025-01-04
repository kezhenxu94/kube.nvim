local base = require("kube.formatters.base")

---@class Formatter
local M = {}

M.headers = {
	"NAME",
	"TYPE",
	"CLUSTER-IP",
	"EXTERNAL-IP",
	"PORT(S)",
	"AGE",
}

function M.format(data)
	local rows = {}
	for _, item in ipairs(data.items) do
		local ports = {}
		for _, port in ipairs(item.spec.ports or {}) do
			table.insert(ports, string.format("%d/%s", port.port, port.protocol or "TCP"))
		end

		table.insert(rows, {
			row = {
				item.metadata.name,
				item.spec.type or "ClusterIP",
				item.spec.clusterIP or "<none>",
				item.status.loadBalancer
						and item.status.loadBalancer.ingress
						and item.status.loadBalancer.ingress[1].ip
					or "<pending>",
				table.concat(ports, ","),
				base.calculate_age(item.metadata.creationTimestamp),
			},
			item = item,
		})
	end
	return rows
end

return M

