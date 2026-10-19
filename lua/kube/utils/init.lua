local M = {}

---@class KubeBufName
---@field context string|nil The kubectl context the buffer is bound to, nil for the current context
---@field namespace string|nil The namespace, nil or "all" for cluster-scoped / all namespaces
---@field kind string The resource type, e.g. `pods` or `deployment.apps`
---@field name string|nil The resource name
---@field subresource string|nil The subresource, e.g. `logs`, `containers`
---@field params table<string, any>|nil Query parameters

---Build a buffer name: kube://[context/<context>/][namespaces/<ns>/]<kind>[/<name>[/<subresource>]][?<params>]
---Without a context the buffer is pinned to the current context when it is opened.
---@param opts KubeBufName
---@return string
function M.buf_name(opts)
  local parts = { "kube:/" }
  if opts.context then
    -- Encoded as context names may contain `/` and `:`, e.g. EKS ARNs
    vim.list_extend(parts, { "context", vim.uri_encode(opts.context, "rfc2396") })
  end
  if opts.namespace and opts.namespace:lower() ~= "all" then
    vim.list_extend(parts, { "namespaces", opts.namespace })
  end
  table.insert(parts, opts.kind)
  if opts.name then
    table.insert(parts, opts.name)
    if opts.subresource then
      table.insert(parts, opts.subresource)
    end
  end

  local buf_name = table.concat(parts, "/")

  local query = {}
  for key, value in pairs(opts.params or {}) do
    table.insert(query, string.format("%s=%s", key, tostring(value)))
  end
  if #query > 0 then
    table.sort(query)
    buf_name = buf_name .. "?" .. table.concat(query, "&")
  end
  return buf_name
end

---Key of the port forwards of a resource in `_G.portforwards`.
---@param context string
---@param namespace string
---@param resource_type string As returned by `resource_type`
---@param name string
---@return string
function M.portforward_key(context, namespace, resource_type, name)
  return table.concat({ context, namespace, resource_type, name }, "/")
end

---Open (or switch to) the buffer for the given name parts.
---@param opts KubeBufName
function M.open(opts)
  -- Escape as `%` (from the encoded context) and `#` are expanded by :edit
  vim.cmd.edit(vim.fn.fnameescape(M.buf_name(opts)))
end

---The fully qualified resource type of a resource object, e.g. `pod` or `deployment.apps`,
---so kubectl never resolves it to a same-named kind in another API group.
---@param resource table
---@return string
function M.resource_type(resource)
  local kind = resource.kind:lower()
  local group = (resource.apiVersion or ""):match("^(.+)/[^/]+$")
  if group then
    return kind .. "." .. group
  end
  return kind
end

---@param timestamp string An RFC 3339 UTC timestamp, e.g. 2026-01-01T00:00:00Z
---@return integer The seconds since the epoch
function M.parse_time(timestamp)
  local time = os.time({
    year = timestamp:sub(1, 4),
    month = timestamp:sub(6, 7),
    day = timestamp:sub(9, 10),
    hour = timestamp:sub(12, 13),
    min = timestamp:sub(15, 16),
    sec = timestamp:sub(18, 19),
    isdst = false,
  })
  -- os.time takes local time, the timestamp is UTC
  return time - os.difftime(os.time(os.date("!*t")), os.time(os.date("*t")))
end

---@param seconds number
---@return string e.g. 42s, 5m3s, 2h, 7d
function M.format_duration(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  elseif seconds < 3600 then
    return string.format("%dm%ds", math.floor(seconds / 60), seconds % 60)
  elseif seconds < 86400 then
    return string.format("%dh", math.floor(seconds / 3600))
  end
  return string.format("%dd", math.floor(seconds / 86400))
end

---@param created string An RFC 3339 UTC timestamp
---@return string The time since `created`
function M.calculate_age(created)
  return M.format_duration(os.difftime(os.time(), M.parse_time(created)))
end

---The table header for the winbar of `win`, aligned with its number column and horizontal scroll.
---@param buf_nr integer
---@param win integer|nil Defaults to the current window
---@return string
function M.get_winbar(buf_nr, win)
  win = win or vim.api.nvim_get_current_win()
  local buffer = _G.kube_buffers[buf_nr]
  if not buffer or not buffer.header_row then
    return ""
  end

  local header_row = buffer.header_row
  local wininfo = vim.fn.getwininfo(win)[1]
  local winbar_padding = string.rep(" ", wininfo and wininfo.textoff or 0)

  local leftcol = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview().leftcol
  end)
  local indicator = ""
  if buffer.watch then
    indicator = string.format(" ⟳ %gs ", require("kube.refresh").interval() / 1000)
  end
  local width = vim.api.nvim_win_get_width(win) - #winbar_padding - vim.fn.strdisplaywidth(indicator)
  local header = header_row.formatted:sub(leftcol + 1):sub(1, math.max(width, 0))

  return string.format("%s%%#%s#%s%%=%%#Comment#%s", winbar_padding, header_row.highlight, header, indicator)
end

---Update the winbar of every window showing the buffer.
---@param kbuf KubeBuffer
function M.update_winbar(kbuf)
  for _, win in ipairs(vim.fn.win_findbuf(kbuf.buf_nr)) do
    vim.wo[win].winbar = M.get_winbar(kbuf.buf_nr, win)
  end
end

return M
