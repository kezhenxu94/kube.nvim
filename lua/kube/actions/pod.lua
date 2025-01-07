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
}

return M
