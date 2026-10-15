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

function M.calculate_age(created)
  local year = created:sub(1, 4)
  local month = created:sub(6, 7)
  local day = created:sub(9, 10)
  local hour = created:sub(12, 13)
  local min = created:sub(15, 16)
  local sec = created:sub(18, 19)

  local creation_time_utc = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false,
  })

  local creation_time = creation_time_utc - os.difftime(os.time(os.date("!*t")), os.time(os.date("*t")))
  local now = os.time()
  local age_secs = os.difftime(now, creation_time)

  if age_secs < 60 then
    return string.format("%ds", age_secs)
  elseif age_secs < 3600 then
    local mins = math.floor(age_secs / 60)
    local secs = age_secs % 60
    return string.format("%dm%ds", mins, secs)
  elseif age_secs < 86400 then
    return string.format("%dh", math.floor(age_secs / 3600))
  else
    return string.format("%dd", math.floor(age_secs / 86400))
  end
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
