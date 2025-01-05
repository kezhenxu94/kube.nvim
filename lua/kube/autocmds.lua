local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

augroup("kube_autocmds", { clear = true })

function M.setup()
	autocmd("BufEnter", {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function()
			local buf = vim.api.nvim_get_current_buf()
			require("kube.keymaps").setup_buffer_keymaps(_G.kube_buffers[buf])
		end,
	})
end

return M
