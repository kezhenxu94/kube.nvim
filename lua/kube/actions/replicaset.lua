local log = require("kube.log")

---@type Actions
local M = {
  drill_down_resource = function(resource, parent)
    log.debug("drilling down to deployment", resource)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace
    local selector = resource.spec.selector.matchLabels

    local buf_name
    local params = {}

    if namespace then
      buf_name = string.format("kube://namespaces/%s/pods", namespace)
    else
      buf_name = string.format("kube://pods")
    end

    local selector_params = {}
    for key, value in pairs(selector) do
      table.insert(selector_params, string.format("%s=%s", key, value))
    end

    if #selector_params > 0 then
      buf_name = buf_name .. "?selector=" .. table.concat(selector_params, ",")
    end

    vim.cmd.edit(buf_name)
  end,

  set_image = function(kbuf, resource, parent)
    log.debug("setting image for replicaset", resource.metadata.name, "in namespace", resource.metadata.namespace)

    local kind = resource.kind:lower()
    local name = resource.metadata.name
    local namespace = resource.metadata.namespace

    local containers = {}
    for _, container in ipairs(resource.spec.template.spec.containers or {}) do
      table.insert(containers, {
        name = container.name,
        image = container.image,
      })
    end
    require("kube.utils.set_image").prompt_set_image(containers, kind, name, namespace, function(changed)
      if changed then
        kbuf:load()
      end
    end)
  end,
}

return M
