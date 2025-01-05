local utils = require("kube.utils")

---@type Formatter
local M = {}

M.headers = { "NAMESPACE", "NAME", "DATA", "AGE", }

function M.format(data)
	local rows = {}
	for _, item in ipairs(data.items) do
		local data_count = 0
		if item.data then
			for _ in pairs(item.data) do
				data_count = data_count + 1
			end
		end

		table.insert(rows, {
			row = {
				item.metadata.namespace,
				item.metadata.name,
				tostring(data_count),
				utils.calculate_age(item.metadata.creationTimestamp),
			},
			item = item,
		})
	end
	return rows
end

return M
