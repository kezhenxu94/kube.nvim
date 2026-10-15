---@class EventHandler
---@field on_buf_saved fun(buf_nr: number, callback: fun(saved: boolean)|nil, opts: {force: boolean|nil}|nil) Handle the buffer save event, `saved` tells whether the buffer should be reloaded, `force` (:w!) skips confirmations of changes

local M = {}

---@param buffer KubeBuffer
---@return EventHandler
function M.for_buffer(buffer)
  if buffer.params and buffer.params.output == "yaml" then
    return require("kube.events.yaml")
  end
  if buffer.subresource_kind == "data" then
    return require("kube.events.secret_data")
  end
  if buffer.subresource_kind == "portforward" or buffer.resource_kind == "portforwards" then
    return require("kube.events.portforward")
  end
  return require("kube.events.default")
end

return M
