local config = require("kube.config").values
local constants = require("kube.constants")
local log = require("kube.log")
local actions = require("kube.actions")

local M = {}

function M.setup_buffer_keymaps(buf_nr)
	local kbuf = _G.kube_buffers[buf_nr]
	local buf = kbuf.buf_nr
	local resource_kind = kbuf.resource_kind
	local namespace = kbuf.namespace
	local mark_mappings = kbuf.mark_mappings
	local subresource_kind = kbuf.subresource_kind
	log.debug("resource_kind", resource_kind, "namespace", namespace, "subresource_kind", subresource_kind)

	vim.keymap.set("n", config.keymaps.drill_down, function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line == 1 then
			return
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			log.debug("resource under cursor", resource)

			if resource.kind then
				actions[resource.kind:lower()].drill_down_resource(resource)
			elseif subresource_kind then
				actions[subresource_kind:lower()].drill_down_resource(resource, {
					kind = kbuf.resource_kind,
					name = kbuf.resource_name,
					namespace = kbuf.namespace,
				})
			end
		end
	end, { buffer = buf })

	vim.keymap.set("n", config.keymaps.show_logs, function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line == 1 then
			return
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			log.debug("resource under cursor", resource)

			if resource.kind then
				actions[resource.kind:lower()].show_logs(resource, false, nil)
			elseif subresource_kind then
				actions[subresource_kind:lower()].show_logs(resource, false, {
					kind = kbuf.resource_kind,
					name = kbuf.resource_name,
					namespace = kbuf.namespace,
				})
			end
		end
	end, { buffer = buf })

	vim.keymap.set("n", config.keymaps.follow_logs, function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if line == 1 then
			return
		end

		local marks = vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, line, line, { details = true })

		if #marks > 0 then
			local mark_id = marks[1][1]
			local resource = mark_mappings[mark_id]
			log.debug("resource under cursor", vim.inspect(resource))

			if resource.kind then
				actions[resource.kind:lower()].show_logs(resource, true, nil)
			elseif subresource_kind then
				actions[subresource_kind:lower()].show_logs(resource, true, {
					kind = kbuf.resource_kind,
					name = kbuf.resource_name,
					namespace = kbuf.namespace,
				})
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
		if kbuf.subresource_kind then
			table.insert(parts, kbuf.subresource_kind)
		end
		vim.notify(string.format("Refreshing %s", table.concat(parts, "/")))

		kbuf:load()
	end, { buffer = buf })
end

return M
