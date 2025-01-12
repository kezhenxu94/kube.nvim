local KubeBuffer = require("kube.buffer").KubeBuffer
local log = require("kube.log")
local utils = require("kube.utils")
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

M.augroup = augroup("kube_autocmds", { clear = true })

function M.setup()
  autocmd("BufReadCmd", {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buf_nr = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      log.debug("loading buffer", buf_name)

      KubeBuffer:new(buf_nr):load()
    end,
  })

  autocmd("BufDelete", {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buf_nr = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      log.debug("deleting buffer", buf_name, ev.buf)

      require("kube.events.default").on_buf_deleted(buf_nr)
    end,
  })

  autocmd("BufWriteCmd", {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buf_nr = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      log.debug("saving buffer", buf_name, ev.buf)

      local buffer = _G.kube_buffers[buf_nr]
      if not buffer then
        log.error("buffer not found", buf_nr)
        return
      end

      local resource_kind = buffer.resource_kind
      local subresource_kind = buffer.subresource_kind
      local handlers = require("kube.events")

      if subresource_kind then
        handlers[subresource_kind:lower()].on_buf_saved(buf_nr)
      elseif resource_kind then
        handlers[resource_kind:lower()].on_buf_saved(buf_nr)
      end
    end,
  })

  autocmd({ "WinScrolled" }, {
    group = "kube_autocmds",
    callback = function()
      local buf_nr = vim.api.nvim_get_current_buf()
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      if not buf_name:match("^kube://") then
        return
      end

      local buffer = _G.kube_buffers[buf_nr]
      log.debug("WinScrolled", buf_name)

      if not buffer then
        return
      end

      vim.wo.winbar = utils.get_winbar(buffer.buf_nr)
    end,
  })

  autocmd("ColorScheme", {
    group = "kube_autocmds",
    callback = function()
      require("kube.highlights").setup()
    end,
  })
end

return M
