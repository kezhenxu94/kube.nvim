---@class PortForward
---@field container_port number The container port to forward
---@field pid number The pid of the port forward

---@type table<string, table<number, PortForward>> -- namespace/pod -> local port -> PortForward
_G.portforwards = {}

local M = {}

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}

  require("kube.config").setup(opts)
  require("kube.highlights").setup(opts)
  require("kube.autocmds").setup()
  require("kube.commands").setup()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      for _, buffer in pairs(_G.kube_buffers or {}) do
        for pid, _ in pairs(buffer.jobs) do
          vim.loop.kill(pid, vim.loop.constants.SIGTERM)
          buffer.jobs[pid] = nil
        end
      end

      for _, portforwards in pairs(_G.portforwards) do
        for _, portforward in pairs(portforwards) do
          vim.loop.kill(portforward.pid, vim.loop.constants.SIGTERM)
        end
      end
    end,
    desc = "Shutdown all kubectl jobs when exiting vim",
  })
end

---@param resource_kind string The resource kind to get
---@param params table<string, string>|nil The parameters to pass to the get command
function M.get(resource_kind, params)
  params = params or {}

  local namespace = params.namespace
  local buf_name
  if not namespace or namespace:lower() == "all" then
    buf_name = string.format("kube://%s", resource_kind)
  else
    buf_name = string.format("kube://namespaces/%s/%s", namespace, resource_kind)
  end

  vim.cmd.edit(buf_name)
end

function M.delete(resource_kind, resource_name, namespace)
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s: %s/%s?", resource_kind, namespace, resource_name),
  }, function(choice)
    if choice == "Yes" then
      require("kubectl").delete(resource_kind, resource_name, namespace, function(result)
        if result then
          vim.notify(string.format("Deleted %s: %s/%s", resource_kind, namespace, resource_name))
        end
      end, function(data)
        vim.notify(
          string.format("Failed to delete %s: %s/%s: \n%s", resource_kind, namespace, resource_name, data),
          vim.log.levels.ERROR
        )
      end)
    end
  end)
end

---@param context string|nil The context to switch to, defaults to nil, and will prompt the user to select a context
function M.ctx(context)
  if context then
    require("kubectl").use_context(context, function(result)
      if result then
        vim.notify(string.format("Switched to context: %s", context))
      end
    end, function(error)
      vim.notify(string.format("Failed to switch to context: %s: \n%s", context, error), vim.log.levels.ERROR)
    end)
    return
  end

  require("kubectl").get_config(function(result)
    if not result then
      vim.schedule(function()
        vim.notify("No config found", vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      local config = vim.fn.json_decode(result)
      local contexts = config.contexts
      if not contexts then
        vim.schedule(function()
          vim.notify("No contexts found", vim.log.levels.ERROR)
        end)
        return
      end

      local current_context = config["current-context"]
      vim.ui.select(contexts, {
        prompt = string.format("Select context (current: %s)", current_context),
        format_item = function(item)
          local is_current = item.name == current_context
          return string.format("%s%s", is_current and "* " or "  ", item.name)
        end,
      }, function(choice)
        if not choice then
          return
        end

        require("kubectl").use_context(choice.name, function(output)
          if output then
            vim.notify(string.format("Switched to context: %s", choice.name))
          end
        end, function(error)
          vim.notify(string.format("Failed to switch to context: %s: \n%s", choice.name, error), vim.log.levels.ERROR)
        end)
      end)
    end)
  end)
end

return M
