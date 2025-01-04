local M = {}

---@param cmd string The command to execute
---@return string|nil The output of the command or nil if the command fails
local function kubectl(cmd)
    local handle = io.popen("kubectl " .. cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

---@param resource_type string The type of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@return string|nil The output of the get command or nil if the resource is not found
function M.get(resource_type, name, namespace)
    local cmd = "get " .. resource_type .. " -o json"
    if name then
        cmd = cmd .. " " .. name
    end
    if namespace then
        cmd = cmd .. " -n " .. namespace
    end
    return kubectl(cmd)
end

---@param file_path string The path to the YAML file
---@return string|nil The output of the apply command or nil if the file is not found
function M.apply(file_path)
    return kubectl("apply -f " .. file_path)
end

---@param resource_type string The type of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@return string|nil The output of the delete command or nil if the resource is not found
function M.delete(resource_type, name, namespace)
    local cmd = "delete " .. resource_type .. " " .. name
    if namespace then
        cmd = cmd .. " -n " .. namespace
    end
    return kubectl(cmd)
end

---@param kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@return string|nil The YAML representation of the resource or nil if the resource is not found
function M.get_resource_yaml(kind, name, namespace)
    local cmd = string.format("get %s %s -n %s -o yaml", 
        string.lower(kind),
        name,
        namespace or "default"
    )
    
    return kubectl(cmd)
end 

return M
