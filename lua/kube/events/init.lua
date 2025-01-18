---@class EventHandler
---@field on_buf_saved fun(buf_nr: number, callback: fun(finished: boolean)|nil) Handle the buffer save event
---@field on_buf_deleted fun(buf_nr: number, callback: fun(finished: boolean)|nil) Handle the buffer delete event

local handlers = {
  portforward = require("kube.events.portforward"),
}

---@type table<string, EventHandler>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    return handlers[key] or require("kube.events.default")
  end,
})
