---@class Actions
---@field drill_down_resource fun(resource: table)

local actions = {
	pod = require("kube.actions.pod"),
}

---@type table<string, Actions>
local M = {}

return setmetatable(M, {
	__index = function(_, key)
		return actions[key] or require("kube.actions.default")
	end,
})
