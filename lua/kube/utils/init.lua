local log = require("kube.log")

local M = {}

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

function M.get_winbar(buf_nr)
  local buffer = _G.kube_buffers[buf_nr]
  if not buffer or not buffer.header_row then
    return ""
  end

  local header_row = buffer.header_row
  local winbar_padding
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())
  if wininfo and wininfo[1].textoff > 0 then
    winbar_padding = string.rep(" ", wininfo[1].textoff)
  end

  local view = vim.fn.winsaveview()
  local scroll_offset = view.leftcol
  local truncated_header = header_row.formatted:sub(scroll_offset + 1)
  log.debug("scroll_offset", scroll_offset, "truncated_header", truncated_header)

  local winwidth = vim.api.nvim_win_get_width(0)
  truncated_header = truncated_header:sub(1, winwidth - #winbar_padding)
  log.debug("winwidth", winwidth, "truncated_header", truncated_header)

  return string.format("%s%%#%s#%s", winbar_padding, header_row.highlight, truncated_header)
end

function M.lualine()
  local context = require("kubectl").get_current_context()
  local icon = vim.fn.nr2char(0xE81D)
  if context then
    return icon .. " " .. context
  end
  return ""
end

return M
