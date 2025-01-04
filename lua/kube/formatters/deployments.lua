local utils = require("kube.utils")

---@type Formatter
local M = {
	headers = { "NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE" },

	format = function(data)
		local rows = {}

		for _, item in ipairs(data.items) do
			local ready = string.format("%d/%d", item.status.readyReplicas or 0, item.status.replicas or 0)

			table.insert(rows, {
				row = {
					item.metadata.name,
					ready,
					tostring(item.status.updatedReplicas or 0),
					tostring(item.status.availableReplicas or 0),
					utils.calculate_age(item.metadata.creationTimestamp),
				},
				item = item,
			})
		end

		return rows
	end,
}

return M
