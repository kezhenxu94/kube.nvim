local log = require("kube.log")

---@type Formatter
local M = {
	headers = { "NAME", "CONTAINER", "PORTS", "URL" },

	format = function(parent_resource)
		local rows = {}

		local namespace = parent_resource.metadata.namespace
		local name = parent_resource.metadata.name
		local portforwards = _G.portforwards[string.format("%s/%s", namespace, name)] or {}

		for _, container in ipairs(parent_resource.spec.containers) do
			local ports = {}
			local urls = {}
			for _, port in ipairs(container.ports or {}) do
				local container_port = port.containerPort
				local portforward = portforwards[container_port]

				if portforward then
					table.insert(ports, string.format("%d:%d", portforward.local_port, container_port))
					table.insert(urls, string.format("http://localhost:%d", portforward.local_port))
				else
					log.debug("portforward not found", namespace, name, container_port)
					table.insert(ports, "")
					table.insert(urls, "")
				end
			end

			table.insert(rows, {
				row = {
					name,
					container.name,
					table.concat(ports, ", "),
					table.concat(urls, ", "),
				},
				item = parent_resource,
			})
		end

		return rows
	end,
}

return M
