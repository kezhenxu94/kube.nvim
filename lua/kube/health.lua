---`:checkhealth kube`
local M = {}

function M.check()
  vim.health.start("kube.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim >= 0.11")
  else
    vim.health.error("Neovim >= 0.11 is required")
  end

  if vim.fn.executable("kubectl") == 0 then
    vim.health.error("kubectl not found in $PATH", "Install kubectl: https://kubernetes.io/docs/tasks/tools/")
    return
  end
  local version = vim.system({ "kubectl", "version", "--client", "-o", "json" }, { text = true }):wait(10000)
  local ok, decoded = pcall(vim.json.decode, version.stdout or "")
  if version.code == 0 and ok and decoded.clientVersion then
    vim.health.ok("kubectl " .. decoded.clientVersion.gitVersion)
  else
    vim.health.warn("Could not get the kubectl version: " .. vim.trim(version.stderr or ""))
  end

  if vim.fn.executable("helm") == 1 then
    local helm = vim.system({ "helm", "version", "--short" }, { text = true }):wait(10000)
    if helm.code == 0 then
      vim.health.ok("helm " .. vim.trim(helm.stdout or ""))
    else
      vim.health.warn("Could not get the helm version: " .. vim.trim(helm.stderr or ""))
    end
  else
    vim.health.info("helm not found in $PATH, Helm releases (kube://helm-releases) are not available")
  end

  local kubectl = require("kubectl")
  local context = kubectl.get_current_context()
  if not context then
    vim.health.warn("No current context", "Set one with `kubectl config use-context` or `:Kube context`")
    return
  end
  vim.health.info("Context: " .. context .. (_G.kube.context and " (switched with :Kube context)" or ""))

  local timeout = require("kube.config").values.request_timeout
  local reachable = vim
    .system({ "kubectl", "--context", context, "--request-timeout=" .. timeout, "version", "-o", "json" }, { text = true })
    :wait(30000)
  if reachable.code == 0 then
    vim.health.ok("The cluster of " .. context .. " is reachable")
  else
    vim.health.warn("The cluster of " .. context .. " is not reachable: " .. vim.trim(reachable.stderr or ""))
  end
end

return M
