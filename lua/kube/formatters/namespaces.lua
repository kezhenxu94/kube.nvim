local utils = require("kube.utils")

---@type Formatter
local M = {
	headers = { "NAME", "STATUS", "AGE" },

	format = function(data)
		local rows = {}

		for _, item in ipairs(data.items) do
			table.insert(rows, {
				row = {
					item.metadata.name,
					item.status.phase or "Unknown",
					utils.calculate_age(item.metadata.creationTimestamp),
				},
				item = item,
			})
		end

		return rows
	end,
}

return M
