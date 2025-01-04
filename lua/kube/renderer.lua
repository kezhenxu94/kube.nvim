local M = {}

local highlights = {
	KubePending = { fg = "#FFA500" },
	KubeRunning = { fg = "#00FF00" },
	KubeFailed = { fg = "#FF0000" },
	KubeSucceeded = { fg = "#00FFFF" },
	KubeUnknown = { fg = "#808080" },
	KubeHeader = { bold = true, underline = true },
}

---@class KubeBuffer
---@field buf number The buffer number
---@field mark_mappings table<number, table> Mapping of mark IDs to row data
local KubeBuffer = {}
KubeBuffer.__index = KubeBuffer

---Create a new KubeBuffer instance
---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
---@param resource_type string The type of resource being rendered
---@param namespace string The namespace of the resource being rendered
---@return KubeBuffer
function KubeBuffer.new(headers, rows, resource_type, namespace)
	local buf_name = string.format("kube://%s/%s", namespace or "default", resource_type)
	local buf = vim.api.nvim_create_buf(false, true)

	local self = setmetatable({
		buf = buf,
		mark_mappings = {},
	}, KubeBuffer)

	_G.kube_buffers = _G.kube_buffers or {}
	_G.kube_buffers[buf] = self

	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = buf,
		callback = function()
			_G.kube_buffers[buf] = nil
		end,
	})

	self:setup(buf_name, headers, rows)
	return self
end

function KubeBuffer:setup(buf_name, headers, rows)
	local existing_buf = vim.fn.bufnr(buf_name)
	if existing_buf ~= -1 then
		vim.api.nvim_buf_delete(existing_buf, { force = true })
	end
	vim.api.nvim_buf_set_name(self.buf, buf_name)

	vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = self.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf })
	vim.api.nvim_set_current_buf(self.buf)

	for group, colors in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, colors)
	end

	local ns_id = vim.api.nvim_create_namespace("kube")

	local formatted_rows = M.format_table(headers, rows)

	local lines = {}
	for _, row in ipairs(formatted_rows) do
		table.insert(lines, row.formatted)
	end
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

	for row_num, row in ipairs(formatted_rows) do
		if row.highlight then
			vim.api.nvim_buf_add_highlight(self.buf, -1, row.highlight, row_num - 1, 0, -1)
			if row_num > 0 and row.raw then
				local mark_id = vim.api.nvim_buf_set_extmark(self.buf, ns_id, row_num - 1, 0, {
					id = row.raw.name,
				})
				self.mark_mappings[mark_id] = row.raw
			end
		end
	end

	vim.keymap.set("n", "<c-]>", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local marks = vim.api.nvim_buf_get_extmarks(self.buf, ns_id, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = self.mark_mappings[mark_id]
			require("kube.actions").drill_down_resource(resource)
		end
	end, { buffer = self.buf })

	vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf })
end

---@class FormattedTableRow
---@field formatted string The formatted line with proper column spacing
---@field highlight string|nil The highlight group to apply to the row
---@field raw table The original row data
---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
---@return FormattedTableRow[] List of objects containing formatted line, highlight, and raw data
function M.format_table(headers, rows)
	local col_widths = {}
	for i, header in ipairs(headers) do
		col_widths[i] = #header
		for _, row in ipairs(rows) do
			col_widths[i] = math.max(col_widths[i], #(row.row[i] or ""))
		end
	end

	local formatted_rows = {
		{
			formatted = M.align_row(headers, col_widths),
			highlight = "KubeHeader",
			raw = headers,
		},
	}

	for _, row in ipairs(rows) do
		table.insert(formatted_rows, {
			formatted = M.align_row(row.row, col_widths),
			highlight = row.row.highlight,
			raw = row.item,
		})
	end

	return formatted_rows
end

---@param row FormattedRow List of columns
---@param col_widths number[] List of column widths
---@return string Formatted row string
function M.align_row(row, col_widths)
	local formatted_cols = {}
	for i, col in ipairs(row) do
		if i <= #col_widths then
			table.insert(formatted_cols, string.format("%-" .. col_widths[i] .. "s", col or ""))
		end
	end
	return table.concat(formatted_cols, "  ")
end

---Create and render a new buffer
---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
---@param resource_type string The type of resource being rendered
---@param namespace string The namespace of the resource being rendered
function M.render(headers, rows, resource_type, namespace)
	return KubeBuffer.new(headers, rows, resource_type, namespace)
end

return M
