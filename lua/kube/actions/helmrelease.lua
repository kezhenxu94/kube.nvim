---@param kbuf KubeBuffer
---@param release table
---@param subresource string|nil
---@param params table<string, any>|nil
local function open(kbuf, release, subresource, params)
  require("kube.utils").open({
    context = kbuf.context,
    namespace = release.namespace,
    kind = "helm-releases",
    name = release.name,
    subresource = subresource,
    params = params,
  })
end

---A Helm release row of `helm-releases`.
---@type Actions
local M = {
  drill_down_resource = function(kbuf, release)
    open(kbuf, release, "manifest")
  end,

  show_yaml = function(kbuf, release)
    open(kbuf, release, "values")
  end,

  describe = function(kbuf, release)
    open(kbuf, release)
  end,

  open = open,
}

return M
