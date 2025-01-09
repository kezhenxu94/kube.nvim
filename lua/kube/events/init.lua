---@class EventHandler
---@field on_buf_saved fun(buf_nr: number) Handle the buffer save event
---@field on_buf_deleted fun(buf_nr: number) Handle the buffer delete event

local handlers = {}

---@type table<string, EventHandler>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    for _, handler in ipairs(handlers) do
      for _, resource_kind in ipairs(handler[1]) do
        if resource_kind == key then
          return handler[2]
        end
      end
    end

    return require("kube.events.default")
  end,
})
