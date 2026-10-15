---@class PortForward
---@field container_port number The container port to forward
---@field job vim.SystemObj The kubectl port-forward job
---@field context string
---@field namespace string
---@field resource_type string
---@field name string

---@type table<string, table<number, PortForward>> -- context/namespace/type/name -> local port -> PortForward
_G.portforwards = _G.portforwards or {}

local M = {}

local initialized = false

---Define the commands and autocmds, called from plugin/kube.lua so that setup() is optional.
function M.init()
  if initialized then
    return
  end
  initialized = true

  require("kube.highlights").setup()
  require("kube.autocmds").setup()
  require("kube.commands").setup()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = require("kube.autocmds").augroup,
    callback = function()
      local kubectl = require("kubectl")
      for _, buffer in pairs(_G.kube_buffers or {}) do
        for pid, job in pairs(buffer.jobs) do
          kubectl.kill(job)
          buffer.jobs[pid] = nil
        end
      end

      for _, portforwards in pairs(_G.portforwards) do
        for _, portforward in pairs(portforwards) do
          kubectl.kill(portforward.job)
        end
      end
    end,
    desc = "Shutdown all kubectl jobs when exiting vim",
  })
end

---Configure kube.nvim, optional: see `require("kube.config").defaults()`.
---@param opts KubeConfig|nil
function M.setup(opts)
  opts = opts or {}

  require("kube.config").setup(opts)
  require("kube.refresh").restart()
  require("kube.highlights").setup(opts)
  M.init()
end

---Apply the current buffer as a manifest to the current context.
---@param force boolean|nil Skip the diff confirmation
function M.apply_buffer(force)
  local context = require("kubectl").get_current_context()
  local name = vim.fn.expand("%:t")
  local apply = require("kube.apply")
  apply.with_temp_file(vim.api.nvim_buf_get_lines(0, 0, -1, false), function(file, cleanup)
    apply.apply(context, nil, file, {
      force = force,
      title = string.format("Apply %s (context: %s)?", name ~= "" and name or "buffer", context),
    }, cleanup)
  end)
end

---Show the diff of the current buffer as a manifest against the current context.
function M.diff_buffer()
  local apply = require("kube.apply")
  apply.with_temp_file(vim.api.nvim_buf_get_lines(0, 0, -1, false), function(file, cleanup)
    require("kubectl").diff(require("kubectl").get_current_context(), nil, file, function(diff)
      cleanup()
      if diff == "" then
        vim.notify("No changes")
      elseif diff then
        apply.show_split(vim.split(vim.trim(diff), "\n"), "diff")
      end
    end, function(err)
      vim.notify("Failed to diff: " .. err, vim.log.levels.ERROR)
    end)
  end)
end

---@param resource_kind string The resource kind to get
---@param params table<string, string>|nil The parameters to pass to the get command
function M.get(resource_kind, params)
  require("kube.log").debug("resource_kind", resource_kind, "params", params)

  params = params or {}

  local namespace = params.namespace
  params.namespace = nil

  require("kube.utils").open({ namespace = namespace, kind = resource_kind, params = params })
end

function M.delete(resource_kind, resource_name, params)
  local kubectl = require("kubectl")
  local context = kubectl.get_current_context()
  local namespace = params.namespace or "default"
  local target = string.format("%s: %s/%s (context: %s)", resource_kind, namespace, resource_name, context)
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Delete %s?", target),
  }, function(choice)
    if choice == "Yes" then
      kubectl.delete(context, resource_kind, resource_name, namespace, function(result)
        if result then
          vim.notify("Deleted " .. target)
        end
      end, function(data)
        vim.notify(string.format("Failed to delete %s: \n%s", target, data), vim.log.levels.ERROR)
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
    require("kube.log").debug("result", result)

    if not result then
      vim.notify("No config found", vim.log.levels.ERROR)
      return
    end

    local config = vim.json.decode(result)
    local contexts = config.contexts

    if contexts == vim.NIL or vim.tbl_isempty(contexts) then
      vim.notify("No contexts found", vim.log.levels.ERROR)
      return
    end

    local current_context = _G.kube.context or config["current-context"]
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
end

return M
