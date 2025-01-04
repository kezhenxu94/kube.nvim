---@class Actions
---@field drill_down_resource fun(resource: table): void

---@type Actions
local M = {}

M.actions = {
	pod = require("kube.actions.pod"),
}

return setmetatable(M, {
	__index = function(_, key)
		return M.actions[key] or require("kube.actions.default")
	end,
})
