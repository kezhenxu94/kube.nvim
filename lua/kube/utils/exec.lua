local log = require("kube.log")

local M = {}

---Create and setup terminal buffer for kubectl exec
---@param namespace string Resource namespace
---@param kind string Resource kind
---@param resource_name string Resource name
---@param container_name string|nil Container name
local function create_exec_terminal(namespace, resource_kind, resource_name, container_name)
  local buf = vim.api.nvim_create_buf(false, true)
  local buf_name = string.format("kube://namespaces/%s/%s/%s", namespace, resource_kind:lower(), resource_name)
  if container_name then
    buf_name = buf_name .. "/" .. container_name
  else
    buf_name = buf_name .. "/exec"
  end
  vim.api.nvim_buf_set_name(buf, buf_name)

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "terminal", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  vim.api.nvim_set_current_buf(buf)

  local cmd = string.format(
    "kubectl exec -it -n %s %s/%s -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'",
    namespace,
    resource_kind:lower(),
    resource_name,
    container_name
  )
  if container_name then
    cmd = cmd .. " -c " .. container_name
  end
  vim.fn.termopen(cmd)
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.cmd("file " .. buf_name)
  vim.cmd("startinsert")
end

---@param containers table[] List of container configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
function M.prompt_exec(containers, kind, name, namespace)
  if #containers == 0 then
    create_exec_terminal(namespace or "default", kind, name, nil)
    return
  end

  if #containers == 1 then
    create_exec_terminal(namespace or "default", kind, name, containers[1].name)
    return
  end

  vim.ui.select(containers, {
    prompt = "Select container to exec into:",
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if not choice then
      return
    end
    log.debug("executing into container", choice.name)

    create_exec_terminal(namespace or "default", kind, name, choice.name)
  end)
end

return M
