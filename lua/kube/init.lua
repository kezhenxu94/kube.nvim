---@class PortForward
---@field container_port number The container port to forward
---@field pid number The pid of the port forward

---@type table<string, table<number, PortForward>> -- namespace/pod -> local port -> PortForward
_G.portforwards = {}

local highlights = {
  KubeBody = { fg = "#40a02b" },
  KubePending = { fg = "#fe640b" },
  KubeRunning = { fg = "#40a02b" },
  KubeFailed = { fg = "#d20f39" },
  KubeSucceeded = { fg = "#9ca0b0" },
  KubeUnknown = { fg = "#6c6f85" },
  KubeHeader = { fg = "#df8e1d", bold = true, underline = true },
}

for group, colors in pairs(highlights) do
  vim.api.nvim_set_hl(0, group, colors)
end

local M = {}

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}

  require("kube.config").setup(opts)

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
---@param namespace string|nil The namespace to get the resource from, defaults to nil, which means the default namespace, use "all" to get from all namespaces
function M.get(resource_kind, namespace)
  local buf_name
  if not namespace or namespace:lower() == "all" then
    buf_name = string.format("kube://%s", resource_kind)
  else
    buf_name = string.format("kube://namespaces/%s/%s", namespace, resource_kind)
  end

  vim.cmd.edit(buf_name)
end

return M
