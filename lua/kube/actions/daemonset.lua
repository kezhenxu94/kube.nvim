local log = require("kube.log")

---@type Actions
local M = {
  set_image = function(kbuf, resource, parent)
    log.debug("setting image for daemonset", resource.metadata.name, "in namespace", resource.metadata.namespace)

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
