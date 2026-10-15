local log = require("kube.log")

local M = {}

---Create and setup terminal buffer for kubectl exec
---@param context string The kubectl context
---@param namespace string Resource namespace
---@param kind string Resource kind
---@param name string Resource name
---@param container_name string|nil Container name
local function create_exec_terminal(context, namespace, kind, name, container_name)
  local buf = vim.api.nvim_create_buf(false, true)
  local buf_name = require("kube.utils").buf_name({
    context = context,
    namespace = namespace,
    kind = kind,
    name = name,
    subresource = "exec",
    params = container_name and { container = container_name } or nil,
  })

  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_current_buf(buf)

  vim.fn.jobstart(require("kubectl").exec_cmd(context, kind, name, namespace, container_name), { term = true })
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.api.nvim_buf_set_name(buf, buf_name)
  vim.cmd("startinsert")
end

---@param context string The kubectl context
---@param containers table[] List of container configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
function M.prompt_exec(context, containers, kind, name, namespace)
  namespace = namespace or "default"

  if #containers <= 1 then
    create_exec_terminal(context, namespace, kind, name, containers[1] and containers[1].name)
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

    create_exec_terminal(context, namespace, kind, name, choice.name)
  end)
end

return M
