local M = {}

---@param opts table|nil
function M.setup(opts)
	opts = opts or {}

	require("kube.config").setup(opts)

	require("kube.autocmds").setup()
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
