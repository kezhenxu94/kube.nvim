local log = require("kube.log")

local M = {}

_G.kube = _G.kube or {}

local function get_state_file_path()
  return vim.fn.stdpath("state") .. "/kube_state.json"
end

local function save_state()
  local state_file = get_state_file_path()
  local state = { context = _G.kube.context }
  local json_str = vim.json.encode(state)

  local file = io.open(state_file, "w")
  if file then
    file:write(json_str)
    file:close()
  end
end

local function load_state()
  local state_file = get_state_file_path()
  local file = io.open(state_file, "r")
  if file then
    local json_str = file:read("*all")
    file:close()

    local ok, state = pcall(vim.json.decode, json_str)
    if ok and type(state) == "table" and type(state.context) == "string" then
      _G.kube.context = state.context
    end
  end
end

load_state()

---@param context string|nil The context to run against, nil for the kubeconfig current-context
---@param args string[] kubectl arguments, without the global `--context` flag
---@return string[]
local function with_context(context, args)
  if context then
    return vim.list_extend({ "kubectl", "--context", context }, args)
  end
  return vim.list_extend({ "kubectl" }, args)
end

---@param namespace string|nil
---@return string[]
local function namespace_args(namespace)
  if not namespace or namespace:lower() == "all" then
    return {}
  end
  return { "-n", namespace }
end

---Run kubectl asynchronously, callbacks are invoked on the main loop.
---@param args string[] The kubectl arguments
---@param callback fun(data: string|nil)|nil Called with stdout on success, nil on failure
---@param on_error fun(data: string)|nil Called with stderr on failure
---@return vim.SystemObj|nil
local function kubectl(context, args, callback, on_error)
  local cmd = with_context(context, args)
  log.debug("kubectl.kubectl", cmd)

  local ok, job = pcall(
    vim.system,
    cmd,
    { text = true },
    vim.schedule_wrap(function(out)
      if out.code ~= 0 and on_error then
        on_error(out.stderr or "")
      end
      if callback then
        callback(out.code == 0 and out.stdout or nil)
      end
    end)
  )
  if not ok then
    vim.notify("Failed to run kubectl: " .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  return job
end

---@param args string[]
---@return string[] Lines of stdout, empty on failure
local function kubectl_sync(context, args)
  local ok, out = pcall(function()
    return vim.system(with_context(context, args), { text = true }):wait()
  end)
  if not ok or out.code ~= 0 then
    return {}
  end
  return vim.split(out.stdout, "\n", { trimempty = true })
end

---@param context string|nil The context to run against
---@param resource_kind string The type of resource
---@param name string|nil The name of the resource, or nil to list all resources of the given type
---@param namespace string|nil The namespace of the resource, or nil to list all resources in all namespaces
---@param params table<string, any>|nil The parameters to pass to the get command
---@param callback function Callback function to handle the output
function M.get(context, resource_kind, name, namespace, params, callback)
  log.debug("kubectl.get", resource_kind, name, namespace, params)

  local args = { "get", resource_kind, "-o", "json" }
  if name then
    table.insert(args, name)
  end
  if namespace and namespace:lower() == "all" then
    table.insert(args, "--all-namespaces")
  else
    vim.list_extend(args, namespace_args(namespace))
  end

  for key, value in pairs(params or {}) do
    table.insert(args, string.format("--%s=%s", key, tostring(value)))
  end

  return kubectl(context, args, callback)
end

---@param context string|nil The context to run against
---@param kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.get_resource_yaml(context, kind, name, namespace, callback)
  log.debug("kubectl.get_resource_yaml", kind, name, namespace)

  local args = { "get", kind:lower(), name, "-o", "yaml" }
  return kubectl(context, vim.list_extend(args, namespace_args(namespace)), callback)
end

---@param context string|nil The context to run against
---@param resource_kind string The kind of resource
---@param resource_name string|nil The name of the resource
---@param container_name string|nil The name of the container
---@param namespace string The namespace of the resource
---@param follow boolean|nil Whether to follow the logs (tail -f style)
---@param callback fun(data: string) Called with complete lines of stdout/stderr (newline separated)
---@return vim.SystemObj|nil
function M.logs(context, resource_kind, resource_name, container_name, namespace, follow, callback)
  log.debug("kubectl.logs", resource_kind, resource_name, container_name, namespace, follow)

  local args = { "logs", string.format("%s/%s", resource_kind, resource_name) }
  if container_name then
    vim.list_extend(args, { "-c", container_name })
  end
  vim.list_extend(args, namespace_args(namespace))

  if not follow then
    return kubectl(context, args, function(data)
      if data then
        callback((data:gsub("\n$", "")))
      end
    end, callback)
  end

  table.insert(args, "-f")

  ---Emit only complete lines, as output arrives in arbitrary chunks
  local function line_buffered()
    local pending = ""
    return function(_, data)
      if not data then
        if pending ~= "" then
          vim.schedule_wrap(callback)(pending)
          pending = ""
        end
        return
      end
      pending = pending .. data
      local last_newline = pending:match(".*()\n")
      if last_newline then
        vim.schedule_wrap(callback)(pending:sub(1, last_newline - 1))
        pending = pending:sub(last_newline + 1)
      end
    end
  end

  local cmd = with_context(context, args)
  log.debug("kubectl.logs", cmd)
  local ok, job = pcall(vim.system, cmd, { text = true, stdout = line_buffered(), stderr = line_buffered() })
  if not ok then
    vim.notify("Failed to run kubectl: " .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  return job
end

---@param context string|nil The context to run against
---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param port number The port to forward
---@param local_port number The local port to forward to
---@param callback fun(data: string|nil)|nil Callback function to handle the output
---@param on_error fun(data: string)|nil Callback function to handle the error output
function M.forward_port(context, resource_kind, name, namespace, port, local_port, callback, on_error)
  log.debug("kubectl.forward_port", resource_kind, name, namespace, port, local_port)

  local args = { "port-forward", string.format("%s/%s", resource_kind, name), string.format("%d:%d", local_port, port) }
  return kubectl(context, vim.list_extend(args, namespace_args(namespace)), callback, on_error)
end

---@param context string|nil The context to run against
---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string The namespace of the resource
---@param callback function Callback function to handle the output
function M.describe(context, resource_kind, name, namespace, callback)
  log.debug("kubectl.describe", resource_kind, name, namespace)

  local args = { "describe", resource_kind, name }
  return kubectl(context, vim.list_extend(args, namespace_args(namespace)), callback)
end

---@param context string|nil The context to run against
---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param namespace string|nil The namespace of the resource, or nil to delete from default namespace
---@param callback fun(data: string?)? Callback function to handle the output
---@param on_error fun(data: string)? Callback function to handle the error output
---@return vim.SystemObj|nil
function M.delete(context, resource_kind, name, namespace, callback, on_error)
  log.debug("kubectl.delete", resource_kind, name, namespace)

  local args = { "delete", resource_kind, name }
  return kubectl(context, vim.list_extend(args, namespace_args(namespace)), callback, on_error)
end

---@return string? The context switched to via `:Kube context`, or the kubeconfig current-context
function M.get_current_context()
  return _G.kube.context or kubectl_sync(nil, { "config", "current-context" })[1]
end

---@param callback function Callback function to handle the output
---@return vim.SystemObj|nil
function M.get_config(callback)
  return kubectl(nil, { "config", "view", "-o", "json" }, callback)
end

function M.use_context(name, callback, on_error)
  _G.kube.context = name
  save_state()
  callback(true)
end

---@type table<string, string[]>
local api_resources_cache = {}

---@return string[] The list of API resources
function M.api_resources_sync()
  local key = _G.kube.context or ""
  if not api_resources_cache[key] then
    local resources = kubectl_sync(_G.kube.context, { "api-resources", "--output=name" })
    if #resources == 0 then
      return resources
    end
    api_resources_cache[key] = resources
  end
  return api_resources_cache[key]
end

---@return string[] The names of contexts
function M.context_names_sync()
  return kubectl_sync(nil, { "config", "get-contexts", "--output=name" })
end

---@param context string|nil The context to run against
---@param namespace string The namespace to apply the YAML resource to
---@param file_path string The path to the YAML file
---@param callback function Callback function to handle the output
---@param on_error fun(data: string)|nil Callback function to handle the error output
---@return vim.SystemObj|nil
function M.apply(context, namespace, file_path, callback, on_error)
  local args = vim.list_extend(namespace_args(namespace), { "apply", "-f", file_path })
  return kubectl(context, args, callback, on_error)
end

---@param context string|nil The context to run against
---@param resource_kind string The kind of resource
---@param name string The name of the resource
---@param container string The name of the container
---@param image string The new image to set
---@param namespace string|nil The namespace of the resource, or nil to use default namespace
---@param callback function|nil Callback function to handle the output
---@param on_error fun(data: string)|nil Callback function to handle the error output
---@return vim.SystemObj|nil
function M.set_image(context, resource_kind, name, namespace, container, image, callback, on_error)
  local args = { "set", "image", string.format("%s/%s", resource_kind, name), string.format("%s=%s", container, image) }
  vim.list_extend(args, namespace_args(namespace))

  log.debug("kubectl.set_image", args)

  return kubectl(context, args, callback, on_error)
end

---Build the argv for an interactive `kubectl exec` session.
---@param context string|nil The context to run against
---@param kind string The kind of resource
---@param name string The name of the resource
---@param namespace string|nil The namespace of the resource
---@param container string|nil The name of the container
---@return string[]
function M.exec_cmd(context, kind, name, namespace, container)
  local args = { "exec", "-it", string.format("%s/%s", kind:lower(), name) }
  vim.list_extend(args, namespace_args(namespace))
  if container then
    vim.list_extend(args, { "-c", container })
  end
  vim.list_extend(args, { "--", "sh", "-c", "command -v bash >/dev/null && exec bash || exec sh" })
  return with_context(context, args)
end

---Kill a job if it is still running.
---@param job vim.SystemObj|nil
function M.kill(job)
  if job and not job:is_closing() then
    job:kill(15)
  end
end

return M
