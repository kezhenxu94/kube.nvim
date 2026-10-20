local log = require("kube.log")

local M = {}

local UNITS = { h = 3600, m = 60, s = 1 }

---The `request_timeout` of the config in milliseconds, helm has no `--request-timeout`.
---@return integer|nil nil for no timeout
local function timeout_ms()
  local timeout = require("kube.config").values.request_timeout
  local seconds = tonumber(timeout)
  if not seconds then
    seconds = 0
    for value, unit in tostring(timeout):gmatch("(%d+)([hms])") do
      seconds = seconds + tonumber(value) * UNITS[unit]
    end
  end
  return seconds > 0 and seconds * 1000 or nil
end

---@param namespace string|nil
---@return string[]
local function namespace_args(namespace)
  if not namespace or namespace:lower() == "all" then
    return {}
  end
  return { "-n", namespace }
end

---Run helm asynchronously, callbacks are invoked on the main loop.
---@param context string|nil
---@param namespace string|nil The namespace of the release, "all" for all namespaces
---@param args string[] The helm arguments
---@param callback fun(data: string|nil)|nil Called with stdout on success, nil on failure
---@param on_error fun(data: string)|nil Called with stderr on failure
---@return vim.SystemObj|nil
local function helm(context, namespace, args, callback, on_error)
  local cmd = { "helm" }
  if context then
    vim.list_extend(cmd, { "--kube-context", context })
  end
  vim.list_extend(cmd, args)
  vim.list_extend(cmd, namespace_args(namespace))
  log.debug("helm", cmd)

  local ok, job = pcall(
    vim.system,
    cmd,
    -- Fail instead of hanging when the API server is unreachable
    { text = true, timeout = timeout_ms() },
    vim.schedule_wrap(function(out)
      local success = out.code == 0
      if not success and on_error then
        local err = vim.trim(out.stderr or "")
        on_error(out.code == 124 and err == "" and "helm timed out" or err)
      end
      if callback then
        callback(success and out.stdout or nil)
      end
    end)
  )
  if not ok then
    vim.notify("Failed to run helm: " .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  return job
end

-- Every status: helm 3 lists deployed and failed releases by default and helm 4 has no `--all`
local STATUSES = { "--deployed", "--failed", "--pending", "--superseded", "--uninstalled", "--uninstalling" }

---The releases, of all statuses, as JSON.
---@param context string|nil
---@param namespace string|nil "all" for all namespaces
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
function M.list(context, namespace, callback, on_error)
  local args = vim.list_extend({ "list" }, STATUSES)
  vim.list_extend(args, { "-o", "json" })
  if namespace and namespace:lower() == "all" then
    table.insert(args, "-A")
  end
  return helm(context, namespace, args, callback, on_error)
end

---@param context string|nil
---@param name string The release
---@param namespace string|nil
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
function M.status(context, name, namespace, callback, on_error)
  return helm(context, namespace, { "status", name }, callback, on_error)
end

---`helm get {what}` of a release.
---@param context string|nil
---@param what "values"|"manifest"|"notes"
---@param name string The release
---@param namespace string|nil
---@param opts {all: boolean|nil, revision: string|integer|nil} `all`: the computed values
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
function M.get(context, what, name, namespace, opts, callback, on_error)
  local args = { "get", what, name }
  if what == "values" then
    vim.list_extend(args, { "-o", "yaml" })
    if opts.all then
      table.insert(args, "--all")
    end
  end
  if opts.revision then
    table.insert(args, "--revision=" .. tostring(opts.revision))
  end
  return helm(context, namespace, args, callback, on_error)
end

---The revisions of a release, as JSON.
---@param context string|nil
---@param name string The release
---@param namespace string|nil
---@param callback fun(data: string|nil)
---@param on_error fun(data: string)|nil
function M.history(context, name, namespace, callback, on_error)
  return helm(context, namespace, { "history", name, "-o", "json" }, callback, on_error)
end

---@param context string|nil
---@param name string The release
---@param namespace string|nil
---@param revision integer|nil nil for the previous revision
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
function M.rollback(context, name, namespace, revision, callback, on_error)
  local args = { "rollback", name }
  if revision then
    table.insert(args, tostring(revision))
  end
  return helm(context, namespace, args, callback, on_error)
end

---@param context string|nil
---@param name string The release
---@param namespace string|nil
---@param callback fun(data: string|nil)|nil
---@param on_error fun(data: string)|nil
function M.uninstall(context, name, namespace, callback, on_error)
  return helm(context, namespace, { "uninstall", name }, callback, on_error)
end

return M
