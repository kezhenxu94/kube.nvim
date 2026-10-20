---Opt-in periodic reload of resource lists ("watch"), toggled per buffer.
local M = {}

---@type uv.uv_timer_t|nil
local timer

---Tables that reflect the cluster state, as opposed to describe / YAML / logs buffers.
---@param kbuf KubeBuffer
---@return boolean
function M.is_table(kbuf)
  return not kbuf.resource_name
    or kbuf.subresource_kind == "containers"
    or kbuf.subresource_kind == "portforward"
    or (kbuf.resource_kind == "helm-releases" and kbuf.subresource_kind == "history")
end

---@param kbuf KubeBuffer
---@return boolean
local function should_refresh(kbuf)
  local buf = kbuf.buf_nr
  if not kbuf.watch or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].modified then
    return false
  end
  if kbuf.loading_job and not kbuf.loading_job:is_closing() then
    return false
  end
  if #vim.fn.win_findbuf(buf) == 0 then
    return false
  end
  -- Do not move lines under a visual selection or a pending operator
  return vim.api.nvim_get_current_buf() ~= buf or vim.api.nvim_get_mode().mode == "n"
end

function M.tick()
  local watching = false
  for _, kbuf in pairs(_G.kube_buffers or {}) do
    watching = watching or kbuf.watch == true
    if should_refresh(kbuf) then
      kbuf:load({ silent = true })
    end
  end
  if not watching then
    M.stop()
  end
end

---@return integer|false The interval in milliseconds, false when disabled
function M.interval()
  return require("kube.config").values.refresh_interval
end

local function start()
  local interval = M.interval()
  if timer or not interval then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(interval, interval, vim.schedule_wrap(M.tick))
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

---Toggle watching the buffer.
---@param kbuf KubeBuffer
function M.toggle(kbuf)
  if not M.is_table(kbuf) then
    vim.notify("Only resource lists can be watched", vim.log.levels.WARN)
    return
  end
  if not M.interval() then
    vim.notify("Watching is disabled, set refresh_interval to enable it", vim.log.levels.WARN)
    return
  end
  kbuf.watch = not kbuf.watch
  if kbuf.watch then
    start()
  end
  require("kube.utils").update_winbar(kbuf)
end

---Apply a new interval to the running timer.
function M.restart()
  if timer then
    M.stop()
    start()
  end
end

return M
