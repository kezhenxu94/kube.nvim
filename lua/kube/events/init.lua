---@class EventHandler
---@field on_buf_saved fun(buf_nr: number, callback: fun(saved: boolean)|nil) Handle the buffer save event, `saved` tells whether the buffer should be reloaded

local M = {}

---@param buffer KubeBuffer
---@return EventHandler
function M.for_buffer(buffer)
  if buffer.params and buffer.params.output == "yaml" then
    return require("kube.events.yaml")
  end
  if buffer.subresource_kind == "portforward" then
    return require("kube.events.portforward")
  end
  return require("kube.events.default")
end

return M
