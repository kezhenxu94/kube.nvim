local KubeBuffer = require("kube.buffer").KubeBuffer
local log = require("kube.log")

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

augroup("kube_autocmds", { clear = true })

function M.setup()
	autocmd({ "BufEnter" }, {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function(ev)
			local buf_name = vim.api.nvim_buf_get_name(ev.buf)
			log.debug("configuring buffer", buf_name)

			require("kube.keymaps").setup_buffer_keymaps(ev.buf)
		end,
	})

	autocmd("BufReadCmd", {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function(ev)
			local buf_name = vim.api.nvim_buf_get_name(ev.buf)
			log.debug("loading buffer", buf_name)

			local buf = KubeBuffer:new(ev.buf)
			buf:setup()
			buf:load()
		end,
	})

	autocmd("BufDelete", {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function()
			local buf_name = vim.api.nvim_buf_get_name(0)
			log.debug("Deleting buffer", buf_name)

			local buf = vim.api.nvim_get_current_buf()
			_G.kube_buffers[buf] = nil
		end,
	})
end

return M
