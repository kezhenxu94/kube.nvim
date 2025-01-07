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

local actions = {
	pod = require("kube.actions.pod"),
	container = require("kube.actions.container"),
	containers = require("kube.actions.container"),
}

---@type table<string, Actions>
local M = {}

return setmetatable(M, {
	__index = function(_, key)
		return actions[key] or require("kube.actions.default")
	end,
})
