local KubeBuffer = require("kube.buffer").KubeBuffer
local log = require("kube.log")

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

M.augroup = augroup("kube_autocmds", { clear = true })

function M.setup()
	autocmd({ "BufReadCmd" }, {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function(ev)
			local buf_name = vim.api.nvim_buf_get_name(ev.buf)
			log.debug("loading buffer", buf_name)

			KubeBuffer:new(ev.buf):load()
		end,
	})

	autocmd({ "BufDelete" }, {
		group = "kube_autocmds",
		pattern = "kube://*",
		callback = function(ev)
			local buf_name = vim.api.nvim_buf_get_name(ev.buf)
			log.debug("deleting buffer", buf_name, ev.buf)

			local buf = _G.kube_buffers[ev.buf]
			log.debug("shutting down jobs")

			if buf then
				for job_id, _ in pairs(buf.jobs) do
					log.debug("shutting down job", job_id)
					vim.loop.kill(job_id, vim.loop.constants.SIGTERM)
					buf.jobs[job_id] = nil
				end
			end

			_G.kube_buffers[ev.buf] = nil
		end,
	})
end

return M
