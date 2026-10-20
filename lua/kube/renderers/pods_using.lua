local formatters = require("kube.formatters")
local kubectl = require("kubectl")

---The pods using a resource, for `kube://.../pods?using={kind}/{name}`: the LSP references.
---@type Renderer
local M = {}

---Kinds of the resources pods use, by the `{kind}` of `using`.
M.KINDS = {
  ConfigMap = "configmap",
  Secret = "secret",
  PersistentVolumeClaim = "persistentvolumeclaim",
  ServiceAccount = "serviceaccount",
  Node = "node",
}

---The `{kind}/{name}` of the resources a pod uses.
---@param pod table
---@return table<string, true>
function M.used_by(pod)
  local spec = pod.spec or {}
  local used = {}
  local function use(kind, name)
    if name then
      used[kind .. "/" .. name] = true
    end
  end

  use("node", spec.nodeName)
  use("serviceaccount", spec.serviceAccountName)
  for _, secret in ipairs(spec.imagePullSecrets or {}) do
    use("secret", secret.name)
  end
  for _, volume in ipairs(spec.volumes or {}) do
    use("configmap", volume.configMap and volume.configMap.name)
    use("secret", volume.secret and volume.secret.secretName)
    use("persistentvolumeclaim", volume.persistentVolumeClaim and volume.persistentVolumeClaim.claimName)
    for _, source in ipairs(volume.projected and volume.projected.sources or {}) do
      use("configmap", source.configMap and source.configMap.name)
      use("secret", source.secret and source.secret.name)
    end
  end
  for _, containers in ipairs({ spec.initContainers or {}, spec.containers or {}, spec.ephemeralContainers or {} }) do
    for _, container in ipairs(containers) do
      for _, env in ipairs(container.env or {}) do
        local from = env.valueFrom or {}
        use("configmap", from.configMapKeyRef and from.configMapKeyRef.name)
        use("secret", from.secretKeyRef and from.secretKeyRef.name)
      end
      for _, from in ipairs(container.envFrom or {}) do
        use("configmap", from.configMapRef and from.configMapRef.name)
        use("secret", from.secretRef and from.secretRef.name)
      end
    end
  end
  return used
end

function M.load(buffer)
  local using = buffer.params.using
  -- The pods of a node are in all namespaces: only ask for those
  local node = using:match("^node/(.+)$")
  local params = node and { ["field-selector"] = "spec.nodeName=" .. node } or nil
  return kubectl.get(buffer.context, "pods", nil, buffer.namespace, params, function(result)
    if not result or not vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      return
    end
    local pods = vim.tbl_filter(function(pod)
      return M.used_by(pod)[using] == true
    end, vim.json.decode(result).items)
    require("kube.renderers.resources").render(buffer, formatters.pods, { items = pods })
  end, buffer:on_error())
end

return M
