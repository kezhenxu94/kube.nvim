local Job = require("plenary.job")
local log = require("kube.log")

local M = {}

---@param cmd string The command to execute
---@param callback fun(data: string|nil)|nil Callback function to handle the output
---@param on_error fun(data: string|nil)|nil Callback function to handle the erroroutput
local function kubectl(cmd, callback, on_error)
  log.debug("kubectl.kubectl", cmd)

  local job = Job:new({
    command = "kubectl",
    args = vim.split(cmd, " "),
    on_exit = function(j, return_val)
      if not callback then
        return
      end

      local result = table.concat(j:result(), "\n")
      if return_val == 0 then
        callback(result)
      else
        callback(nil)
      end
    end,
    on_stderr = function(_, data)
      if not on_error then
        return
      end

      if data then
        on_error(data)
      end
    end,
  })
  job:start()
  return job
end

---@param resource_kind string The type of resource
---@param name string|nil The name of the resource, or nil to list all resources of the given type
---@param namespace string|nil The namespace of the resource, or nil to list all resources in all namespaces
---@param params table<string, any>|nil The parameters to pass to the get command
---@param callback function Callback function to handle the output
function M.get(resource_kind, name, namespace, params, callback)
  log.debug("kubectl.get", resource_kind, name, namespace, params)

  local cmd = "get " .. resource_kind .. " -o json"
  if name then
    cmd = cmd .. " " .. name
  end
  if namespace then
    if namespace:lower() == "all" then
      cmd = cmd .. " --all-namespaces"
    else
      cmd = cmd .. " -n " .. namespace
    end
  end

  if params then
    for key, value in pairs(params) do
      cmd = cmd .. " --" .. key .. "=" .. value
    end
  end

  return kubectl(cmd, callback)
end

---@param kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.get_resource_yaml(kind, name, namespace, callback)
  log.debug("kubectl.get_resource_yaml", kind, name, namespace)

  local cmd = string.format("get %s %s -n %s -o yaml", string.lower(kind), name, namespace or "default")
  return kubectl(cmd, callback)
end

---@param resource_name string|nil The name of the resource
---@param container_name string|nil The name of the container, or nil to get logs from the first container
---@param namespace string The namespace of the resource
---@param follow boolean|nil Whether to follow the logs (tail -f style)
---@param callback function Callback function to handle the output
---@return Job|nil The job object, or nil if the job is not started
function M.logs(resource_name, container_name, namespace, follow, callback)
  log.debug("kubectl.logs", resource_name, container_name, namespace, follow)

  local cmd = "logs " .. resource_name
  if container_name then
    cmd = cmd .. " -c " .. container_name
  end
  if namespace then
    cmd = cmd .. " -n " .. namespace
  end

  if follow then
    cmd = cmd .. " -f"
    local job = Job:new({
      command = "kubectl",
      args = vim.split(cmd, " "),
      on_stdout = function(_, data)
        if data then
          callback(data)
        end
      end,
      on_stderr = function(_, data)
        if data then
          callback(data)
        end
      end,
    })
    job:start()
    return job
  else
    local job = Job:new({
      command = "kubectl",
      args = vim.split(cmd, " "),
      on_stdout = function(_, data)
        if data then
          callback(data)
        end
      end,
      on_stderr = function(_, data)
        if data then
          callback(data)
        end
      end,
    })
    job:start()
    return job
  end
end

---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param port number The port to forward
---@param local_port number The local port to forward to
---@param callback fun(data: string|nil)|nil Callback function to handle the output
---@param on_error fun(data: string|nil)|nil Callback function to handle the error output
function M.forward_port(resource_kind, name, namespace, port, local_port, callback, on_error)
  log.debug("kubectl.forward_port", resource_kind, name, namespace, port, local_port)

  local cmd = string.format("port-forward %s/%s -n %s %d:%d", resource_kind, name, namespace, local_port, port)
  return kubectl(cmd, callback, on_error)
end

---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.describe(resource_kind, name, namespace, callback)
  log.debug("kubectl.describe", resource_kind, name, namespace)

  local cmd = string.format("describe %s %s -n %s", resource_kind, name, namespace)
  return kubectl(cmd, callback)
end

---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string|nil The namespace of the resource, or nil to delete from default namespace
---@param callback function Callback function to handle the output
---@param on_error fun(data: string|nil) Callback function to handle the error output
---@return Job|nil The job object, or nil if the job is not started
function M.delete(resource_kind, name, namespace, callback, on_error)
  log.debug("kubectl.delete", resource_kind, name, namespace)

  local cmd = string.format("delete %s %s -n %s", resource_kind, name, namespace or "default")
  return kubectl(cmd, callback, on_error)
end

---@return string The current context
function M.get_current_context()
  local job = Job:new({
    command = "kubectl",
    args = { "config", "current-context" },
  })
  job:sync()
  local result = job:result()
  return result and result[1] or nil
end

---@param callback function Callback function to handle the output
---@return Job|nil The job object, or nil if the job is not started
function M.get_config(callback)
  return kubectl("config view -o json", callback)
end

---@param name string The name of the context to use
---@param callback function Callback function to handle the output
---@param on_error fun(data: string|nil) Callback function to handle the error output
---@return Job|nil The job object, or nil if the job is not started
function M.use_context(name, callback, on_error)
  return kubectl("config use-context " .. name, callback, on_error)
end

---@return string[] The list of API resources
function M.api_resources_sync()
  local job = Job:new({
    command = "kubectl",
    args = { "api-resources", "--output=name" },
  })
  job:sync()
  local result = job:result()
  return result or {}
end

---@return string[] The names of contexts
function M.context_names_sync()
  local job = Job:new({
    command = "kubectl",
    args = { "config", "get-contexts", "--output=name" },
  })
  job:sync()
  local result = job:result()
  return result or {}
end

---@param namespace string The namespace to apply the YAML resource to
---@param file_path string The path to the YAML file
---@param callback function Callback function to handle the output
---@param on_error fun(data: string|nil)|nil Callback function to handle the error output
---@return Job|nil The job object, or nil if the job is not started
function M.apply(namespace, file_path, callback, on_error)
  local job = kubectl(string.format("-n %s apply -f %s", namespace, file_path), function(result)
    if callback then
      callback(result)
    end
  end, on_error)

  return job
end

---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param container string The name of the container
---@param image string The new image to set
---@param namespace string|nil The namespace of the resource, or nil to use default namespace
---@param callback function|nil Callback function to handle the output
---@param on_error fun(data: string|nil)|nil Callback function to handle the error output
---@return Job|nil The job object, or nil if the job is not started
function M.set_image(resource_kind, name, namespace, container, image, callback, on_error)
  local cmd = string.format("set image %s/%s %s=%s", resource_kind, name, container, image)
  if namespace then
    cmd = cmd .. " -n " .. namespace
  end

  log.debug("kubectl.set_image", resource_kind, name, container, image, namespace, cmd)

  return kubectl(cmd, callback, on_error)
end

return M
