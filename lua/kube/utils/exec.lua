local log = require("kube.log")

local M = {}

---Run an interactive kubectl command in a terminal buffer
---@param cmd string[] The kubectl command
---@param name_opts KubeBufName The name of the terminal buffer
local function open_terminal(cmd, name_opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_current_buf(buf)

  vim.fn.jobstart(cmd, { term = true })
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.api.nvim_buf_set_name(buf, require("kube.utils").buf_name(name_opts))
  vim.cmd("startinsert")
end

---Create and setup terminal buffer for kubectl exec
---@param context string The kubectl context
---@param namespace string Resource namespace
---@param kind string Resource kind
---@param name string Resource name
---@param container_name string|nil Container name
local function create_exec_terminal(context, namespace, kind, name, container_name)
  open_terminal(require("kubectl").exec_cmd(context, kind, name, namespace, container_name), {
    context = context,
    namespace = namespace,
    kind = kind,
    name = name,
    subresource = "exec",
    params = container_name and { container = container_name } or nil,
  })
end

---@param containers table[]
---@param prompt string
---@param on_choice fun(container: table|nil) Called with the only container without prompting
local function select_container(containers, prompt, on_choice)
  if #containers <= 1 then
    on_choice(containers[1])
    return
  end
  vim.ui.select(containers, {
    prompt = prompt,
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if choice then
      on_choice(choice)
    end
  end)
end

---@param context string The kubectl context
---@param containers table[] List of container configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
function M.prompt_exec(context, containers, kind, name, namespace)
  namespace = namespace or "default"
  select_container(containers, "Select container to exec into:", function(container)
    log.debug("executing into container", container and container.name)
    create_exec_terminal(context, namespace, kind, name, container and container.name)
  end)
end

---Open a shell in an ephemeral debug container of a pod, sharing the process namespace of a container.
---@param context string The kubectl context
---@param pod table The pod
function M.prompt_debug(context, pod)
  vim.ui.input({ prompt = "Debug image: ", default = "busybox" }, function(image)
    if not image or image == "" then
      return
    end
    select_container(pod.spec.containers, "Select the container to debug:", function(container)
      local target = container and container.name
      local namespace = pod.metadata.namespace
      open_terminal(require("kubectl").debug_cmd(context, pod.metadata.name, namespace, image, target), {
        context = context,
        namespace = namespace,
        kind = "pod",
        name = pod.metadata.name,
        subresource = "debug",
        params = { image = image, target = target },
      })
    end)
  end)
end

return M
