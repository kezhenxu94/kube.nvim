---@class ParentResource
---@field kind string
---@field name string?
---@field namespace string?
---@class Actions
---@field drill_down_resource fun(resource: table, parent: ParentResource|nil)
---@field show_logs fun(resource: table, follow: boolean, parent: ParentResource|nil)|nil

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
