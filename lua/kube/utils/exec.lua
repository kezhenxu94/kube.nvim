local log = require("kube.log")

local M = {}

---Start the shell of a `…/exec` or `…/debug` buffer (see `require("kube.utils").buf_name`) in the
---current buffer, from BufReadCmd: the name is all it takes, like `term://` buffers.
---@param name string The buffer name
---@param parts KubeBufNameParts
function M.start(name, parts)
  local kubectl = require("kubectl")
  local params = parts.params or {}
  local cmd
  if not parts.resource_name then
    vim.notify(
      "Expected: kube://context/{context}/[namespaces/{ns}/]{kind}/{name}/" .. parts.subresource_kind,
      vim.log.levels.ERROR
    )
    return
  elseif parts.subresource_kind == "exec" then
    cmd = kubectl.exec_cmd(parts.context, parts.resource_kind, parts.resource_name, parts.namespace, params.container)
  elseif type(params.image) == "string" then
    cmd = kubectl.debug_cmd(parts.context, parts.resource_name, parts.namespace, params.image, params.target)
  else
    vim.notify("Expected the image of the debug container: ?image={image}", vim.log.levels.ERROR)
    return
  end
  vim.fn.jobstart(cmd, { term = true })
  vim.opt_local.number = false
  vim.opt_local.relativenumber = false

  -- jobstart() names the buffer `term://…`: keep the name, so editing it again finds the shell.
  -- :file leaves a buffer with the old name, unlike jobstart().
  local term_name = vim.api.nvim_buf_get_name(0)
  if term_name == name then
    return
  end
  vim.cmd("keepalt file " .. vim.fn.fnameescape(name))
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == term_name then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

---Edit the shell buffer, it is started by BufReadCmd unless it already exists.
---@param name_opts KubeBufName
local function open_terminal(name_opts)
  require("kube.utils").open(name_opts)
  vim.cmd("startinsert")
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
    open_terminal({
      context = context,
      namespace = namespace,
      kind = kind,
      name = name,
      subresource = "exec",
      params = container and { container = container.name } or nil,
    })
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
      open_terminal({
        context = context,
        namespace = pod.metadata.namespace,
        kind = "pod",
        name = pod.metadata.name,
        subresource = "debug",
        params = { image = image, target = container and container.name },
      })
    end)
  end)
end

return M
