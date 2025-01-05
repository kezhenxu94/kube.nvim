---@class KubeConfig
---@field keymaps table<string, string>

local M = {}

---@return KubeConfig
function M.defaults()
	return {
		keymaps = {
			drill_down = "gd",
			refresh = "<c-r>",
		},
	}
end

M.values = M.defaults()

function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", M.defaults(), opts)
end

return M
