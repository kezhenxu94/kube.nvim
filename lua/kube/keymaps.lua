local config = require("kube.config").values
local constants = require("kube.constants")

local M = {}

function M.setup_buffer_keymaps(self)
	local buf = self.buf
	local resource_type = self.resource_type
	local namespace = self.namespace
	local mark_mappings = self.mark_mappings

	vim.keymap.set("n", config.keymaps.drill_down, function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line == 1 then
			return
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			require("kube.actions")[resource.kind:lower()].drill_down_resource(resource)
		end
	end, { buffer = buf })

	vim.keymap.set("n", config.keymaps.refresh, function()
		vim.notify("Refreshing " .. resource_type .. " in " .. namespace)
		require("kube").show_resources(resource_type, namespace)
	end, { buffer = buf })
end

return M
