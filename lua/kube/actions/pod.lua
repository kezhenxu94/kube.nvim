local log = require("kube.log")

---@type Actions
local M = {
	drill_down_resource = function(resource)
		log.debug("drilling down to pod", resource)

		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace
		local buf_name
		if namespace then
			buf_name = string.format("kube://namespaces/%s/%s/%s/containers", namespace, kind, name)
		else
			buf_name = string.format("kube://%s/%s/containers", kind, name)
		end

		vim.cmd.edit(buf_name)
	end,

	show_logs = function(resource, follow, _)
		log.debug("showing logs for pod", resource)

		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace
		local buf_name
		if namespace then
			buf_name = string.format("kube://namespaces/%s/%s/%s/logs", namespace, kind, name)
		else
			buf_name = string.format("kube://%s/%s/logs", kind, name)
		end

		if follow then
			buf_name = buf_name .. "?follow=true"
		end

		vim.cmd.edit(buf_name)
	end,

	port_forward = function(resource, _)
		log.debug("forwarding port for pod", resource)

		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace
		local buf_name
		if namespace then
			buf_name = string.format("kube://namespaces/%s/%s/%s/portforward", namespace, kind, name)
		else
			buf_name = string.format("kube://%s/%s/portforward", kind, name)
		end

		vim.cmd.edit(buf_name)
	end,

	forward_port = function(resource, _)
		log.debug("forwarding port for pod", resource)

		local kind = resource.kind:lower()
		local name = resource.metadata.name
		local namespace = resource.metadata.namespace

		local ports = {}
		for _, container in ipairs(resource.spec.containers) do
			for _, port in ipairs(container.ports or {}) do
				table.insert(ports, {
					container = container.name,
					port = port.containerPort,
					protocol = port.protocol or "TCP",
				})
			end
		end

		if #ports == 0 then
			vim.notify("No ports available for port forwarding", vim.log.levels.WARN)
			return
		end

		local port_strings = {}
		for i, port in ipairs(ports) do
			table.insert(port_strings, string.format("%d) %s: %d/%s", i, port.container, port.port, port.protocol))
		end

		local function prompt_port_forward()
			vim.ui.select(port_strings, {
				prompt = "Select container port to forward (q to quit):",
			}, function(choice, idx)
				if not choice or not idx then
					return
				end

				local port = ports[idx]
				if not port then
					return
				end

				vim.ui.input({
					prompt = string.format("Local port (default %d): ", port.port),
					default = tostring(port.port),
				}, function(input)
					if not input then
						return
					end

					local local_port = tonumber(input)
					if not local_port then
						vim.notify("Invalid port number", vim.log.levels.ERROR)
						return
					end

					log.debug("forwarding port", port.container, port.port, local_port)

					vim.notify(string.format("Forwarding port %d to %d", port.port, local_port), vim.log.levels.INFO)
					local job = require("kubectl").forward_port(
						kind,
						name,
						namespace,
						port.container,
						port.port,
						local_port,
						function(data) end,
						function(data)
							vim.schedule(function()
								vim.notify(data, vim.log.levels.ERROR)
							end)
						end
					)

					local key = string.format("%s/%s", namespace, name)
					_G.portforwards[key] = _G.portforwards[key] or {}
					_G.portforwards[key][local_port] = {
						container_port = port.port,
						pid = job.pid,
					}

					prompt_port_forward()
				end)
			end)
		end

		prompt_port_forward()
	end,
}

return M
