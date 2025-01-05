---@type Formatter
local M = {
	headers = { "NAME", "STATUS", "IMAGE", "PORTS" },

	format = function(parent_resource)
		local container_statuses = {}

		if parent_resource.spec.initContainers then
			for _, container in ipairs(parent_resource.spec.initContainers) do
				local status
				if parent_resource.status.initContainerStatuses then
					for _, containerStatus in ipairs(parent_resource.status.initContainerStatuses) do
						if containerStatus.name == container.name then
							if containerStatus.state.terminated and containerStatus.state.terminated.exitCode == 0 then
								status = "Succeeded"
							elseif containerStatus.state.terminated then
								status = "Failed"
							elseif containerStatus.state.running then
								status = "Running"
							elseif containerStatus.state.waiting then
								status = "Pending"
							end
							break
						end
					end
				end
				container_statuses[container.name] = status
			end
		end

		if parent_resource.spec.containers then
			for _, container in ipairs(parent_resource.spec.containers) do
				local status
				if parent_resource.status.containerStatuses then
					for _, containerStatus in ipairs(parent_resource.status.containerStatuses) do
						if containerStatus.name == container.name then
							if containerStatus.state.terminated and containerStatus.state.terminated.exitCode == 0 then
								status = "Succeeded"
							elseif containerStatus.state.terminated then
								status = "Failed"
							elseif containerStatus.state.running then
								status = "Running"
							elseif containerStatus.state.waiting then
								status = "Pending"
							end
							break
						end
					end
				end
				container_statuses[container.name] = status
			end
		end

		local rows = {}

		for _, container in ipairs(parent_resource.spec.containers) do
			local ports = ""
			if container.ports then
				local port_strings = {}
				for _, port in ipairs(container.ports) do
					table.insert(port_strings, string.format("%d/%s", port.containerPort, port.protocol or "TCP"))
				end
				ports = table.concat(port_strings, ", ")
			end

			local status = container_statuses[container.name] or "Unknown"

			table.insert(rows, {
				row = {
					container.name,
					status,
					container.image,
					ports,
					highlight = "Kube" .. status,
				},
				item = container,
			})
		end

		return rows
	end,
}

return M
