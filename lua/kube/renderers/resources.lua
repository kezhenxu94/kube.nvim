local constants = require("kube.constants")
local formatters = require("kube.formatters")
local log = require("kube.log")
local utils = require("kube.utils")

local M = {}

local MAX_COLUMN_WIDTH = 99
local COLUMN_SEPARATOR = "  "

---Identity of a row's item that survives reloads, so the cursor can stay on the same row.
---@param item table|nil
---@return string|nil
local function row_identity(item)
  if type(item) ~= "table" then
    return nil
  end
  if item.metadata then
    return table.concat({ item.kind or "", item.metadata.namespace or "", item.metadata.name or "" }, "/")
  end
  if item.local_port then
    return string.format("%s:%s", item.id, item.local_port)
  end
  -- Helm releases of the same name in different namespaces
  if item.namespace then
    return item.namespace .. "/" .. item.name
  end
  return item.name
end

---Remember the row under the cursor of every window showing the buffer.
---@param buffer KubeBuffer
---@return {win: integer, identity: string|nil, cursor: integer[]}[]
local function save_cursors(buffer)
  local saved = {}
  for _, win in ipairs(vim.fn.win_findbuf(buffer.buf_nr)) do
    local cursor = vim.api.nvim_win_get_cursor(win)
    local marks = vim.api.nvim_buf_get_extmarks(
      buffer.buf_nr,
      constants.KUBE_NAMESPACE,
      { cursor[1] - 1, 0 },
      { cursor[1] - 1, -1 },
      {}
    )
    local marked_line = marks[1] and buffer.mark_mappings[marks[1][1]]
    table.insert(saved, { win = win, identity = marked_line and row_identity(marked_line.item), cursor = cursor })
  end
  return saved
end

---Move the cursors back to the rows of the same items, or keep the line when the item is gone.
---@param saved {win: integer, identity: string|nil, cursor: integer[]}[]
---@param formatted_rows FormattedTableRow[]
local function restore_cursors(saved, formatted_rows)
  for _, entry in ipairs(saved) do
    if vim.api.nvim_win_is_valid(entry.win) then
      local line = math.min(entry.cursor[1], math.max(#formatted_rows, 1))
      for row_num, row in ipairs(formatted_rows) do
        if entry.identity and row_identity(row.raw) == entry.identity then
          line = row_num
          break
        end
      end
      pcall(vim.api.nvim_win_set_cursor, entry.win, { line, entry.cursor[2] })
    end
  end
end

-- Columns that change on every reload, not worth showing as a change
local VOLATILE_COLUMNS = { AGE = true, ["LAST SEEN"] = true, CPU = true, MEMORY = true }
local FLASH_DURATION = 1500

---@param headers string[]
---@param cells string[]
---@return string
local function row_signature(headers, cells)
  local values = {}
  for i, header in ipairs(headers) do
    if not VOLATILE_COLUMNS[header] then
      table.insert(values, cells[i] or "")
    end
  end
  return table.concat(values, "\0")
end

---The signatures of the rendered rows by identity, nil before the first render.
---@param buffer KubeBuffer
---@return table<string, string>|nil
local function signatures(buffer)
  if vim.tbl_isempty(buffer.mark_mappings) then
    return nil
  end
  local result = {}
  for _, marked_line in pairs(buffer.mark_mappings) do
    local identity = row_identity(marked_line.item)
    if identity then
      result[identity] = marked_line.signature
    end
  end
  return result
end

---Highlight the rows for a moment.
---@param buffer KubeBuffer
---@param rows integer[] 0-indexed
local function flash(buffer, rows)
  for _, row in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buffer.buf_nr, constants.KUBE_CHANGED_NAMESPACE, row, 0, {
      line_hl_group = "KubeChanged",
      priority = vim.hl.priorities.user,
    })
  end
  if #rows == 0 then
    return
  end
  local generation = (buffer.flash_generation or 0) + 1
  buffer.flash_generation = generation
  vim.defer_fn(function()
    -- A later reload flashes its own rows
    if buffer.flash_generation == generation and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      vim.api.nvim_buf_clear_namespace(buffer.buf_nr, constants.KUBE_CHANGED_NAMESPACE, 0, -1)
    end
  end, FLASH_DURATION)
end

---@param buffer KubeBuffer The buffer to render into
---@return Formatter
function M.formatter_for(buffer)
  if buffer.subresource_kind and formatters[buffer.subresource_kind] then
    return formatters[buffer.subresource_kind]
  end
  return formatters[buffer.resource_kind]
end

---Contexts whose cluster has no metrics API, not asked again
---@type table<string, boolean>
local metrics_unavailable = {}

---@alias KubeMetrics table<string, string[]> CPU and memory usage by "namespace/name"

---@param output string The output of `kubectl top --no-headers`
---@param kind "pods"|"nodes"
---@param namespace string The namespace of the buffer, "all" for all namespaces
---@return KubeMetrics
local function parse_metrics(output, kind, namespace)
  local metrics = {}
  for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
    local fields = vim.split(vim.trim(line), "%s+")
    if kind == "nodes" then
      -- NAME CPU(cores) CPU(%) MEMORY(bytes) MEMORY(%)
      metrics["/" .. fields[1]] = { fields[2], fields[4] }
    elseif namespace:lower() == "all" then
      metrics[fields[1] .. "/" .. fields[2]] = { fields[3], fields[4] }
    else
      metrics[namespace .. "/" .. fields[1]] = { fields[2], fields[3] }
    end
  end
  return metrics
end

---A job that is closing once all `jobs` are.
---@param jobs vim.SystemObj[]
---@return vim.SystemObj
local function all_jobs(jobs)
  return {
    pid = jobs[1].pid,
    is_closing = function()
      for _, job in ipairs(jobs) do
        if not job:is_closing() then
          return false
        end
      end
      return true
    end,
    kill = function()
      for _, job in ipairs(jobs) do
        require("kubectl").kill(job)
      end
    end,
  }
end

---@param buffer KubeBuffer The buffer to render into
function M.load(buffer)
  log.debug("loading buffer", buffer.resource_kind, buffer.resource_name, buffer.namespace, buffer.params)

  local kubectl = require("kubectl")
  local formatter = M.formatter_for(buffer)
  local kind = not buffer.resource_name and formatter.metrics
  local with_metrics = kind and not metrics_unavailable[buffer.context]

  -- Render once the resources and, if asked, their metrics are loaded
  local data, metrics
  local pending = with_metrics and 2 or 1
  local function loaded()
    pending = pending - 1
    if pending == 0 and data and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
      M.render(buffer, formatter, data, metrics)
    end
  end

  local job = kubectl.get(
    buffer.context,
    buffer.resource_kind,
    buffer.resource_name,
    buffer.namespace,
    buffer.params,
    function(result)
      -- The jobs of an unloaded buffer are killed, ending without output
      if result and vim.api.nvim_buf_is_loaded(buffer.buf_nr) then
        data = vim.json.decode(result)
      end
      loaded()
    end,
    buffer:on_error()
  )
  if not job then
    return nil
  end
  buffer.jobs[job.pid] = job
  if not with_metrics then
    return job
  end

  local top = kubectl.top(buffer.context, kind, buffer.namespace, (buffer.params or {}).selector, function(result)
    metrics = result and parse_metrics(result, kind, buffer.namespace)
    loaded()
  end, function(err)
    log.debug("no metrics", err)
    if err:find("Metrics API not available", 1, true) then
      metrics_unavailable[buffer.context] = true
    end
  end)
  if not top then
    loaded()
    return job
  end
  buffer.jobs[top.pid] = top
  return all_jobs({ job, top })
end

---Insert the CPU and memory usage columns before AGE.
---@param headers string[]
---@param rows FormattedRow[]
---@param metrics KubeMetrics
---@return string[] headers
local function add_metrics(headers, rows, metrics)
  local at = #headers + 1
  for i, header in ipairs(headers) do
    if header == "AGE" then
      at = i
    end
  end
  for _, row in ipairs(rows) do
    local usage = metrics[(row.item.metadata.namespace or "") .. "/" .. row.item.metadata.name] or {}
    table.insert(row.row, at, usage[1] or "")
    table.insert(row.row, at + 1, usage[2] or "")
  end
  headers = vim.list_extend({}, headers)
  table.insert(headers, at, "CPU")
  table.insert(headers, at + 1, "MEMORY")
  return headers
end

---Render the rows of `data` as a table, keeping the cursors on the same rows.
---@param buffer KubeBuffer The buffer to render into
---@param formatter Formatter
---@param data table|nil The decoded kubectl output
---@param metrics KubeMetrics|nil The usage of the resources, adds CPU and MEMORY columns
function M.render(buffer, formatter, data, metrics)
  local self = buffer
  -- Edits made while a background reload was running win over the reload
  if self.silent and vim.bo[self.buf_nr].modified then
    return
  end
  local headers = formatter.headers
  local cursors = save_cursors(self)
  local previous = signatures(self)

  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_PENDING_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_CHANGED_NAMESPACE, 0, -1)
  vim.diagnostic.reset(constants.KUBE_DIAGNOSTICS_NAMESPACE, self.buf_nr)
  self.mark_mappings = {}
  self.mark_columns = {}
  self.data = data

  local rows = formatter.format(data, self)
  if metrics then
    headers = add_metrics(headers, rows, metrics)
  end

  self:setup()

  local header_row, formatted_rows = M.format_table(headers, rows)
  self.header_row = header_row

  local lines = {}
  for _, row in ipairs(formatted_rows) do
    table.insert(lines, row.formatted)
  end
  self:set_lines(lines, true)
  restore_cursors(cursors, formatted_rows)
  if #lines == 0 then
    self:set_status(formatter.empty or "No resources found", "Comment")
  end

  local diagnostics = {}
  local changed = {}
  for row_num, row in ipairs(formatted_rows) do
    local row_mark
    if row.raw then
      row_mark = vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_NAMESPACE, row_num - 1, 0, {
        invalidate = true,
        line_hl_group = "KubeBody",
      })
      local signature = row_signature(headers, row.cells)
      self.mark_mappings[row_mark] = {
        item = row.raw,
        line = row.formatted,
        signature = signature,
      }
      local identity = row_identity(row.raw)
      if previous and identity and previous[identity] ~= signature then
        table.insert(changed, row_num - 1)
      end
    end

    for i, range in ipairs(row.ranges) do
      -- Text typed at either end of the cell, as by `ciw`, stays in the cell
      local mark_id =
        vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, row_num - 1, range[1], {
          end_col = range[2],
          right_gravity = false,
          end_right_gravity = true,
          hl_group = row.highlights and row.highlights[headers[i]]
            or formatter.editable and formatter.editable[headers[i]] and "KubeEditable"
            or nil,
        })
      self.mark_columns[mark_id] = {
        item = row.raw,
        column = headers[i],
        text = vim.trim(row.formatted:sub(range[1] + 1, range[2])),
        row_mark = row_mark,
      }
    end

    for _, diagnostic in ipairs(row.diagnostics or {}) do
      table.insert(diagnostics, {
        bufnr = self.buf_nr,
        lnum = row_num - 1,
        col = 0,
        message = diagnostic.message,
        severity = diagnostic.severity,
      })
    end
  end

  if #diagnostics > 0 then
    vim.diagnostic.set(constants.KUBE_DIAGNOSTICS_NAMESPACE, self.buf_nr, diagnostics, {})
  end
  -- After the diagnostics, whose signs may change the width of the sign column the header is aligned with.
  -- A narrower sign column ('signcolumn' auto) is only computed by a redraw.
  if #vim.fn.win_findbuf(self.buf_nr) > 0 then
    vim.cmd.redraw()
  end
  utils.update_winbar(self)
  -- Only reloads of a watched list: a reload asked for shows the changes it was asked for
  if self.silent then
    flash(self, changed)
  end
end

---Show the rows deleted from the buffer, which `:w` deletes, where they were.
---@param buffer KubeBuffer
function M.show_pending(buffer)
  local buf = buffer.buf_nr
  vim.api.nvim_buf_clear_namespace(buf, constants.KUBE_PENDING_NAMESPACE, 0, -1)

  -- Marks are created in the order of the rows
  local ids = vim.tbl_keys(buffer.mark_mappings)
  table.sort(ids)
  local deleted = {}
  for _, id in ipairs(ids) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(buf, constants.KUBE_NAMESPACE, id, { details = true })
    if mark[3] and mark[3].invalid then
      deleted[mark[1]] = deleted[mark[1]] or {}
      table.insert(deleted[mark[1]], { { buffer.mark_mappings[id].line, "KubeDeleted" } })
    end
  end

  local last = vim.api.nvim_buf_line_count(buf) - 1
  for row, virt_lines in pairs(deleted) do
    vim.api.nvim_buf_set_extmark(buf, constants.KUBE_PENDING_NAMESPACE, math.min(row, last), 0, {
      virt_lines = virt_lines,
      -- Rows deleted at the end go below the last line
      virt_lines_above = row <= last,
    })
  end

  -- Lines above the first line are only shown as filler of the top line
  if deleted[0] then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        if vim.fn.line("w0") == 1 then
          vim.fn.winrestview({ topfill = #deleted[0] })
        end
      end)
    end
  end
end

---@param text string
---@return integer The display width
local function display_width(text)
  -- Most cells are ASCII, where the width is the length
  if not text:find("[\128-\255]") then
    return #text
  end
  return vim.api.nvim_strwidth(text)
end

---@param text string
---@param width integer
---@return string `text` cut to `width` display cells, ending with "..."
local function truncate(text, width)
  if not text:find("[\128-\255]") then
    return text:sub(1, width - 3) .. "..."
  end
  local chars, used = {}, 0
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    used = used + vim.api.nvim_strwidth(char)
    if used > width - 3 then
      break
    end
    table.insert(chars, char)
  end
  return table.concat(chars) .. "..."
end

---@class FormattedTableRow
---@field formatted string The formatted line with proper column spacing
---@field cells string[] The values of the columns
---@field ranges integer[][] The 0-indexed byte range [start, end) of each column in `formatted`
---@field highlights table<string, string>|nil Highlight groups of cells, by header
---@field highlight string|nil The highlight group of the header row
---@field raw table The original row data
---@field diagnostics vim.Diagnostic[]|nil List of diagnostics for the row

---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
---@return FormattedTableRow The formatted header row
---@return FormattedTableRow[] List of objects containing formatted line, highlight, and raw data
---@return number[] List of column widths
function M.format_table(headers, rows)
  local col_widths = {}
  for i, header in ipairs(headers) do
    col_widths[i] = #header
    for _, row in ipairs(rows) do
      col_widths[i] = math.max(col_widths[i], display_width(row.row[i] or ""))
    end
  end

  local formatted_rows = {}

  for _, row in ipairs(rows) do
    local formatted, ranges = M.align_row(row.row, col_widths)
    table.insert(formatted_rows, {
      formatted = formatted,
      ranges = ranges,
      cells = row.row,
      highlights = row.highlights,
      diagnostics = row.diagnostics,
      raw = row.item,
    })
  end

  return {
    formatted = M.align_row(headers, col_widths),
    highlight = "KubeHeader",
    raw = headers,
  },
    formatted_rows,
    col_widths
end

---@param row string[] The values of the columns
---@param col_widths number[] List of column widths
---@return string Formatted row string
---@return integer[][] The 0-indexed byte range [start, end) of each column
function M.align_row(row, col_widths)
  local formatted_cols, ranges = {}, {}
  local pos = 0
  for i, col_width in ipairs(col_widths) do
    local width = math.min(MAX_COLUMN_WIDTH, col_width)
    local col_str = row[i] or ""
    local col_display_width = display_width(col_str)
    if col_display_width > width then
      col_str = truncate(col_str, width)
      col_display_width = display_width(col_str)
    end
    col_str = col_str .. string.rep(" ", width - col_display_width)
    table.insert(formatted_cols, col_str)
    table.insert(ranges, { pos, pos + #col_str })
    pos = pos + #col_str + #COLUMN_SEPARATOR
  end
  return table.concat(formatted_cols, COLUMN_SEPARATOR), ranges
end

return M
