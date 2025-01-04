local M = {}

-- Execute kubectl commands and return the output
local function kubectl(cmd)
    local handle = io.popen("kubectl " .. cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Get resources
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

-- Create resource from YAML file
function M.apply(file_path)
    return kubectl("apply -f " .. file_path)
end

-- Delete resource
function M.delete(resource_type, name, namespace)
    local cmd = "delete " .. resource_type .. " " .. name
    if namespace then
        cmd = cmd .. " -n " .. namespace
    end
    return kubectl(cmd)
end

return M
