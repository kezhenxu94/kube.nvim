---@class PodActions
local M = {}

function M.drill_down_resource(resource)
	local name = resource.metadata.name
	local namespace = resource.metadata.namespace
	local containers = resource.spec.containers

    local buf_name = string.format("kube://pod/%s/%s.yaml", namespace, name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buf_name)

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
    vim.api.nvim_set_option_value("filetype", "yaml", { buf = buf })

    vim.api.nvim_set_current_buf(buf)

    -- Create a simplified view of the Pod's containers
    local lines = {
        string.format("Pod: %s", name),
        string.format("Namespace: %s", namespace),
        "Containers:",
        "---"
    }

    for _, container in ipairs(containers) do
        table.insert(lines, string.format("- Name: %s", container.name))
        table.insert(lines, string.format("  Image: %s", container.image))
        if container.ports then
            table.insert(lines, "  Ports:")
            for _, port in ipairs(container.ports) do
                table.insert(lines, string.format("    - %d/%s", port.containerPort, port.protocol or "TCP"))
            end
        end
        table.insert(lines, "---")
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

return M 