local constants = require("kube.constants")
local log = require("kube.log")

local M = {}

local highlights = {
	KubePending = { fg = "#fe640b" },
	KubeRunning = { fg = "#40a02b" },
	KubeFailed = { fg = "#d20f39" },
	KubeSucceeded = { fg = "#9ca0b0" },
	KubeUnknown = { fg = "#6c6f85" },
	KubeHeader = { fg = "#df8e1d", bold = true, underline = true },
}

---@type table<number, KubeBuffer>
_G.kube_buffers = {}

---@class KubeBuffer
---@field buf_nr number The buffer number
---@field mark_mappings table<number, table> Mapping of mark IDs to row data
---@field namespace string The namespace of the resource in buffer
---@field resource_kind string The kind of resource in buffer
---@field resource_name string|nil The name of the resource in buffer
---@field subresource_name string|nil The name of the subresource in buffer
local KubeBuffer = {}
KubeBuffer.__index = KubeBuffer

---Create a new KubeBuffer instance
---@param buf_nr number The buffer number
---@return KubeBuffer
function KubeBuffer:new(buf_nr)
	buf_nr = buf_nr or vim.api.nvim_get_current_buf()

	local buf_name = vim.api.nvim_buf_get_name(buf_nr)
	local namespace, resource_kind, resource_name, subresource_name, remainders
	local ns_pattern = "kube://namespaces/([^/]+)/([^/]+)/?(.*)"
	namespace, resource_kind, remainders = buf_name:match(ns_pattern)
	if not namespace then
		local cluster_pattern = "kube://([^/]+)/?(.*)"
		resource_kind, remainders = buf_name:match(cluster_pattern)
		namespace = "all"
	end

	log.debug("namespace", namespace, "resource_kind", resource_kind, "remainders", remainders)

	if not resource_kind then
		error(
			"Invalid buffer name format. Expected: kube://namespaces/{namespace}/{resource_kind} or kube://{resource_kind}"
		)
	end

	if remainders then
		local resource_pattern = "([^/]+)/?(.*)"
		resource_name, remainders = remainders:match(resource_pattern)
		log.debug("resource_name", resource_name, "remainders", remainders)

		if remainders then
			local subresource_pattern = "([^/]+)(.*)"
			subresource_name, remainders = remainders:match(subresource_pattern)
		end
	end

	local this = setmetatable({
		buf_nr = buf_nr,
		mark_mappings = {},
		namespace = namespace,
		resource_kind = resource_kind,
		resource_name = resource_name,
		subresource_name = subresource_name,
	}, KubeBuffer)
	_G.kube_buffers[buf_nr] = this

	return this
end

function KubeBuffer:setup()
	vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_nr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = self.buf_nr })
	vim.api.nvim_set_option_value("swapfile", false, { buf = self.buf_nr })
	vim.api.nvim_set_option_value("filetype", "kube", { buf = self.buf_nr })
	vim.api.nvim_set_current_buf(self.buf_nr)

	for group, colors in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, colors)
	end
end

function KubeBuffer:load()
	local resource_kind = self.resource_kind
	local resource_name = self.resource_name
	local subresource_name = self.subresource_name
	local namespace = self.namespace
	local formatters = require("kube.formatters")
	local formatter = formatters[resource_kind]
	if subresource_name and formatters[subresource_name] then
		formatter = formatters[subresource_name]
		log.debug("formatter for subresource found", subresource_name, formatter)
	end

	log.debug("loading buffer", resource_kind, resource_name, namespace, subresource_name)

	local headers = formatter.headers
	local kubectl = require("kubectl")
	kubectl.get(resource_kind, resource_name, namespace, function(result)
		vim.schedule(function()
			local data = vim.fn.json_decode(result)
			local rows = formatter.format(data)
			self:setup()

			local formatted_rows = M.format_table(headers, rows)

			local lines = {}
			for _, row in ipairs(formatted_rows) do
				table.insert(lines, row.formatted)
			end
			vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, lines)

			for row_num, row in ipairs(formatted_rows) do
				if row.highlight then
					vim.api.nvim_buf_add_highlight(self.buf_nr, -1, row.highlight, row_num - 1, 0, -1)
				end
				if row_num > 0 and row.raw then
					local mark_id =
						vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_NAMESPACE, row_num - 1, 0, {})
					self.mark_mappings[mark_id] = row.raw
				end
			end

			vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_nr })
		end)
	end)
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

M.KubeBuffer = KubeBuffer

return M
