---@class ParentResource
---@field kind string
---@field name string?
---@field namespace string?
---@class Actions
---@field drill_down_resource fun(resource: table, parent: ParentResource|nil) -- Drill down into the resource
---@field show_yaml fun(resource: table, parent: ParentResource|nil)|nil -- Show the yaml buffer for the resource
---@field show_logs fun(resource: table, follow: boolean, parent: ParentResource|nil)|nil -- Show the logs buffer for the resource
---@field show_events fun(resource: table, parent: ParentResource|nil)|nil -- Show the events buffer for the resource
---@field port_forward fun(resource: table, parent: ParentResource|nil)|nil -- Show the port forward buffer for the resource
---@field forward_port fun(resource: table, parent: ParentResource|nil)|nil -- Forward the port for the resource
---@field describe fun(resource: table, parent: ParentResource|nil)|nil -- Describe the resource

local actions = {
  pod = require("kube.actions.pod"),
  container = require("kube.actions.container"),
  containers = require("kube.actions.container"),
}

---@type table<string, Actions>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    local default_actions = require("kube.actions.default")
    local resource_actions = actions[key] or default_actions

    return setmetatable({}, {
      __index = function(_, action_name)
        local action = resource_actions[action_name]
        if action then
          return action
        end

        return default_actions[action_name]
      end,
    })
  end,
})
