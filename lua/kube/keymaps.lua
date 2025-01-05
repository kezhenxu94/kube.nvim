local M = {}

function M.setup_buffer_keymaps(buf, ns_id, mark_mappings, resource_type, namespace)
	vim.keymap.set("n", "gd", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			require("kube.actions")[resource.kind:lower()].drill_down_resource(resource)
		end
	end, { buffer = buf })

	vim.keymap.set("n", "<c-r>", function()
		vim.notify("Refreshing " .. resource_type .. " in " .. namespace)
		require("kube").show_resources(resource_type, namespace)
	end, { buffer = buf })
end

return M

