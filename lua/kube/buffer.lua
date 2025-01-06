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
---@field subresource_kind string|nil The name of the subresource in buffer
local KubeBuffer = {}
KubeBuffer.__index = KubeBuffer

---Create a new KubeBuffer instance
---@param buf_nr number The buffer number
---@return KubeBuffer
function KubeBuffer:new(buf_nr)
	buf_nr = buf_nr or vim.api.nvim_get_current_buf()

	local buf_name = vim.api.nvim_buf_get_name(buf_nr)
	local namespace, resource_kind, resource_name, subresource_kind, remainders
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
			subresource_kind, remainders = remainders:match(subresource_pattern)
		end
	end

	local this = setmetatable({
		buf_nr = buf_nr,
		mark_mappings = {},
		namespace = namespace,
		resource_kind = resource_kind,
		resource_name = resource_name,
		subresource_kind = subresource_kind,
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
	require("kube.renderers").load(self)
end

M.KubeBuffer = KubeBuffer

return M
