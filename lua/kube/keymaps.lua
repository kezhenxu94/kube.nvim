local config = require("kube.config").values
local constants = require("kube.constants")
local log = require("kube.log")

local M = {}

function M.setup_buffer_keymaps(buf_nr)
	local kbuf = _G.kube_buffers[buf_nr]
	local buf = kbuf.buf_nr
	local resource_kind = kbuf.resource_kind
	local namespace = kbuf.namespace
	local mark_mappings = kbuf.mark_mappings

	vim.keymap.set("n", config.keymaps.drill_down, function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line == 1 then
			return
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			log.debug("resource under cursor", vim.inspect(resource))

			if resource and resource.kind then
				require("kube.actions")[resource.kind:lower()].drill_down_resource(resource)
			end
		end
	end, { buffer = buf })

	vim.keymap.set("n", config.keymaps.refresh, function()
		local parts = {}
		if namespace then
			table.insert(parts, namespace)
		end
		if resource_kind then
			table.insert(parts, resource_kind)
		end
		if kbuf.resource_name then
			table.insert(parts, kbuf.resource_name)
		end
		if kbuf.subresource_name then
			table.insert(parts, kbuf.subresource_name)
		end
		vim.notify(string.format("Refreshing %s", table.concat(parts, "/")))

		kbuf:load()
	end, { buffer = buf })
end

return M
