local Job = require("plenary.job")
local M = {}

---@param cmd string The command to execute
---@param callback function Callback function to handle the output
local function kubectl(cmd, callback)
	Job:new({
		command = "kubectl",
		args = vim.split(cmd, " "),
		on_exit = function(j, return_val)
			local result = table.concat(j:result(), "\n")
			if return_val == 0 then
				callback(result)
			else
				callback(nil)
			end
		end,
	}):start()
end

---@param resource_type string The type of resource
---@param name string|nil The name of the resource, or nil to list all resources of the given type
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.get(resource_type, name, namespace, callback)
	local cmd = "get " .. resource_type .. " -o json"
	if name then
		cmd = cmd .. " " .. name
	end
	if namespace then
		cmd = cmd .. " -n " .. namespace
	end
	kubectl(cmd, callback)
end

---@param file_path string The path to the YAML file
---@param callback function Callback function to handle the output
function M.apply(file_path, callback)
	kubectl("apply -f " .. file_path, callback)
end

---@param resource_type string The type of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.delete(resource_type, name, namespace, callback)
	local cmd = "delete " .. resource_type .. " " .. name
	if namespace then
		cmd = cmd .. " -n " .. namespace
	end
	kubectl(cmd, callback)
end

---@param kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.get_resource_yaml(kind, name, namespace, callback)
	local cmd = string.format("get %s %s -n %s -o yaml", string.lower(kind), name, namespace or "default")
	kubectl(cmd, callback)
end

return M
