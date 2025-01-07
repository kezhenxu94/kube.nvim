---@class PortForward
---@field container_port number The container port to forward
---@field pid number The pid of the port forward

---@type table<string, table<number, PortForward>> -- namespace/pod -> local port -> PortForward
_G.portforwards = {}

local M = {}

---@param opts table|nil
function M.setup(opts)
	opts = opts or {}

	require("kube.config").setup(opts)

	require("kube.autocmds").setup()

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			for _, buffer in pairs(_G.kube_buffers or {}) do
				for pid, _ in pairs(buffer.jobs) do
					vim.loop.kill(pid, vim.loop.constants.SIGTERM)
					buffer.jobs[pid] = nil
				end
			end

			for _, portforwards in pairs(_G.portforwards) do
				for _, portforward in pairs(portforwards) do
					vim.loop.kill(portforward.pid, vim.loop.constants.SIGTERM)
				end
			end
		end,
		desc = "Shutdown all kubectl jobs when exiting vim",
	})
end

function M.show_resources(resource_kind, namespace)
	local buf_name
	if not namespace or namespace:lower() == "all" then
		buf_name = string.format("kube://%s", resource_kind)
	else
		buf_name = string.format("kube://namespaces/%s/%s", namespace, resource_kind)
	end

	vim.cmd.edit(buf_name)
end

return M
