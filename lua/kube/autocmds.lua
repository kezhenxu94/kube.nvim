local KubeBuffer = require("kube.buffer").KubeBuffer
local log = require("kube.log")
local utils = require("kube.utils")
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local M = {}

M.augroup = augroup("kube_autocmds", { clear = true })

---The name of the buffer a name is an alias of, itself if none:
---without `context/<context>/` it is pinned to the current context, so the buffer keeps operating
---on the same cluster after the context is switched; `ns` is short for `namespaces`; no kind is
---the resource types, `api-resources`.
---@param buf_name string
---@return string|nil name
---@return string|nil err
function M.canonical_name(buf_name)
  if buf_name == "kube://portforwards" then
    return buf_name
  end

  local rest = buf_name:sub(#"kube://" + 1):gsub("^/+", "")
  local context = rest:match("^context/[^/?]*/?")
  if context then
    rest = rest:sub(#context + 1)
    if not vim.endswith(context, "/") then
      context = context .. "/"
    end
  else
    local current = require("kubectl").get_current_context()
    if not current then
      return nil, "No current kubectl context"
    end
    context = string.format("context/%s/", vim.uri_encode(current, "rfc2396"))
  end
  rest = rest:gsub("^ns$", "namespaces"):gsub("^ns([/?])", "namespaces%1")
  if rest == "" then
    rest = "api-resources"
  end
  return "kube://" .. context .. rest
end

function M.setup()
  autocmd("BufReadCmd", {
    group = "kube_autocmds",
    pattern = "kube://*",
    -- So that the BufReadCmd of the buffer an alias redirects to runs
    nested = true,
    callback = function(ev)
      local buf_nr = ev.buf
      local buf_name = vim.api.nvim_buf_get_name(buf_nr)
      log.debug("loading buffer", buf_name)

      local name, err = M.canonical_name(buf_name)
      if not name then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      -- The name is an alias: edit the canonical buffer instead, the alias is wiped, it never
      -- becomes the alternate file or a jump.
      if name ~= buf_name then
        local canonical = vim.fn.bufadd(name)
        vim.bo[canonical].buflisted = true
        vim.cmd.buffer({ canonical, mods = { keepalt = true, keepjumps = true } })
        vim.schedule(function()
          pcall(vim.api.nvim_buf_delete, buf_nr, { force = true })
        end)
        return
      end

      local parts = require("kube.buffer").parse_name(name)
      if parts.subresource_kind == "exec" or parts.subresource_kind == "debug" then
        require("kube.utils.exec").start(name, parts)
        return
      end
      KubeBuffer:new(buf_nr):load()
    end,
  })

  -- An unloaded buffer (`:bunload`, leaving it with 'nohidden', `:e`) keeps its state, e.g. watching,
  -- for when it is loaded again, a deleted one (`:bdelete`, `:bwipeout`) starts over.
  autocmd("BufUnload", {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buffer = _G.kube_buffers[ev.buf]
      if buffer then
        buffer:stop_jobs()
      end
    end,
  })

  autocmd({ "BufDelete", "BufWipeout" }, {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      log.debug("deleting buffer", vim.api.nvim_buf_get_name(ev.buf), ev.buf)
      local buffer = _G.kube_buffers[ev.buf]
      if buffer then
        buffer:stop_jobs()
        _G.kube_buffers[ev.buf] = nil
      end
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

      require("kube.events").for_buffer(buffer).on_buf_saved(buf_nr, function(saved)
        if saved then
          vim.schedule(function()
            buffer:load()
          end)
        end
      end, { force = vim.v.cmdbang == 1 })
    end,
  })

  autocmd({ "TextChanged", "TextChangedI" }, {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buffer = _G.kube_buffers[ev.buf]
      if buffer and not vim.tbl_isempty(buffer.mark_mappings) then
        require("kube.renderers.resources").show_pending(buffer)
      end
    end,
  })

  autocmd("BufWinEnter", {
    group = "kube_autocmds",
    pattern = "kube://*",
    callback = function(ev)
      local buffer = _G.kube_buffers[ev.buf]
      -- Wrapped rows break the table layout and its alignment with the winbar header
      if buffer and require("kube.refresh").is_table(buffer) then
        vim.wo[0][0].wrap = false
      end
    end,
  })

  autocmd({ "WinScrolled", "WinResized" }, {
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

      utils.update_winbar(buffer)
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
