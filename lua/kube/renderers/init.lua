---@class Renderer
---@field load fun(buffer: KubeBuffer): vim.SystemObj|nil Load content for the buffer

---Renderers of subresources, others (containers, portforward) are tables of the parent resource
local subresources = {
  logs = "kube.renderers.logs",
  history = "kube.renderers.history",
  data = "kube.renderers.secret_data",
}

---@type Renderer
local M = {
  load = function(buffer)
    if buffer.resource_kind == "helm-releases" then
      return require("kube.renderers.helm").load(buffer)
    end

    if not buffer.resource_name then
      if buffer.resource_kind == "events" and (buffer.params or {})["for"] then
        return require("kube.renderers.related_events").load(buffer)
      end
      if buffer.resource_kind == "pods" and (buffer.params or {}).using then
        return require("kube.renderers.pods_using").load(buffer)
      end
      if buffer.resource_kind == "api-resources" then
        return require("kube.renderers.api_resources").load(buffer)
      end
      if buffer.resource_kind == "portforwards" then
        return require("kube.renderers.portforwards").load(buffer)
      end
      return require("kube.renderers.resources").load(buffer)
    end

    if not buffer.subresource_kind then
      local output = (buffer.params or {}).output
      if output == "yaml" then
        return require("kube.renderers.resource_yaml").load(buffer)
      elseif output then
        vim.notify("Unsupported output type: " .. output, vim.log.levels.ERROR)
        return nil
      end
      return require("kube.renderers.resource").load(buffer)
    end

    local subresource = subresources[buffer.subresource_kind]
    return require(subresource or "kube.renderers.resources").load(buffer)
  end,
}

return M
