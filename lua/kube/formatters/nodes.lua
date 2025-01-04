local utils = require("kube.utils")

---@type Formatter
local M = {
	headers = { "NAME", "STATUS", "ROLES", "AGE", "VERSION" },

	format = function(data)
		local rows = {}
		for _, item in ipairs(data.items) do
			local roles = {}
			for label, _ in pairs(item.metadata.labels or {}) do
				if label:match("^node%-role.kubernetes.io/") then
					table.insert(roles, label:match("node%-role.kubernetes.io/(.+)"))
				end
			end

			table.insert(rows, {
				row = {
					item.metadata.name,
					table.concat(item.status.conditions[#item.status.conditions].type, ","),
					table.concat(roles, ","),
					utils.calculate_age(item.metadata.creationTimestamp),
					item.status.nodeInfo.kubeletVersion,
				},
				item = item,
			})
		end
		return rows
	end,
}

return M
