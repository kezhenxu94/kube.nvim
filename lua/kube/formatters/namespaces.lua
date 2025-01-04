local base = require("kube.formatters.base")

---@class Formatter
local M = {}

M.headers = {
	"NAME",
	"STATUS",
	"AGE",
}

function M.format(data)
	local rows = {}

	for _, item in ipairs(data.items) do
		table.insert(rows, {
			row = {
				item.metadata.name,
				item.status.phase or "Unknown",
				base.calculate_age(item.metadata.creationTimestamp),
			},
			item = item,
		})
	end

	return rows
end

return M

