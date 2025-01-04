local M = {}

---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table): FormattedRow[] Function that takes raw data and returns formatted rows
---@class FormattedRow
---@field row table The row data containing column values
---@field item table The original resource item data

function M.calculate_age(created)
	local year = created:sub(1, 4)
	local month = created:sub(6, 7)
	local day = created:sub(9, 10)
	local hour = created:sub(12, 13)
	local min = created:sub(15, 16)
	local sec = created:sub(18, 19)

	local creation_time_utc = os.time({
		year = year,
		month = month,
		day = day,
		hour = hour,
		min = min,
		sec = sec,
		isdst = false,
	})

	local creation_time = creation_time_utc - os.difftime(os.time(os.date("!*t")), os.time(os.date("*t")))
	local now = os.time()
	local age_secs = os.difftime(now, creation_time)

	if age_secs < 60 then
		return string.format("%ds", age_secs)
	elseif age_secs < 3600 then
		local mins = math.floor(age_secs / 60)
		local secs = age_secs % 60
		return string.format("%dm%ds", mins, secs)
	elseif age_secs < 86400 then
		return string.format("%dh", math.floor(age_secs / 3600))
	else
		return string.format("%dd", math.floor(age_secs / 86400))
	end
end

return M

