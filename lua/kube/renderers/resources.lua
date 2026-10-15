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

---@param buffer KubeBuffer The buffer to render into
---@return Formatter
local function formatter_for(buffer)
  if buffer.subresource_kind and formatters[buffer.subresource_kind] then
    return formatters[buffer.subresource_kind]
  end
  return formatters[buffer.resource_kind]
end

---@param buffer KubeBuffer The buffer to render into
function M.load(buffer)
  log.debug("loading buffer", buffer.resource_kind, buffer.resource_name, buffer.namespace, buffer.params)

  local job = require("kubectl").get(
    buffer.context,
    buffer.resource_kind,
    buffer.resource_name,
    buffer.namespace,
    buffer.params,
    function(result)
      if result and vim.api.nvim_buf_is_valid(buffer.buf_nr) then
        M.render(buffer, formatter_for(buffer), vim.json.decode(result))
      end
    end,
    buffer:on_error()
  )

  if job then
    buffer.jobs[job.pid] = job
  end

  return job
end

---Render the rows of `data` as a table, keeping the cursors on the same rows.
---@param buffer KubeBuffer The buffer to render into
---@param formatter Formatter
---@param data table|nil The decoded kubectl output
function M.render(buffer, formatter, data)
  local self = buffer
  -- Edits made while a background reload was running win over the reload
  if self.silent and vim.bo[self.buf_nr].modified then
    return
  end
  local headers = formatter.headers
  local cursors = save_cursors(self)

  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, 0, -1)
  vim.diagnostic.reset(constants.KUBE_DIAGNOSTICS_NAMESPACE, self.buf_nr)
  self.mark_mappings = {}
  self.mark_columns = {}
  self.data = data

  local rows = formatter.format(data, self)

  self:setup()

  local header_row, formatted_rows, col_widths = M.format_table(headers, rows)
  self.header_row = header_row
  utils.update_winbar(self)

  local lines = {}
  for _, row in ipairs(formatted_rows) do
    table.insert(lines, row.formatted)
  end
  self:set_lines(lines, true)
  restore_cursors(cursors, formatted_rows)
  if #lines == 0 then
    self:set_status("No resources found", "Comment")
  end

  local diagnostics = {}
  for row_num, row in ipairs(formatted_rows) do
    if row.raw then
      local mark_id = vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_NAMESPACE, row_num - 1, 0, {
        invalidate = true,
        line_hl_group = row.highlight or "KubeBody",
      })
      self.mark_mappings[mark_id] = {
        item = row.raw,
      }
    end

    local col_pos = 0
    for i, col_width in ipairs(col_widths) do
      -- Same widths and separator as `align_row`
      local width = math.min(MAX_COLUMN_WIDTH, col_width)
      local mark_id = vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, row_num - 1, col_pos, {
        end_col = col_pos + width,
        invalidate = true,
      })
      self.mark_columns[mark_id] = {
        item = row.raw,
        column = headers[i],
      }
      col_pos = col_pos + width + #COLUMN_SEPARATOR
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
end

---@class FormattedTableRow
---@field formatted string The formatted line with proper column spacing
---@field highlight string|nil The highlight group to apply to the row
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
      col_widths[i] = math.max(col_widths[i], #(row.row[i] or ""))
    end
  end

  local formatted_rows = {}

  for _, row in ipairs(rows) do
    table.insert(formatted_rows, {
      formatted = M.align_row(row.row, col_widths),
      highlight = row.row.highlight,
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

---@param row FormattedRow List of columns
---@param col_widths number[] List of column widths
---@return string Formatted row string
function M.align_row(row, col_widths)
  local formatted_cols = {}
  for i, col in ipairs(row) do
    if i <= #col_widths then
      local width = math.min(MAX_COLUMN_WIDTH, col_widths[i])
      local col_str = col or ""
      if #col_str > width then
        col_str = col_str:sub(1, width - 3) .. "..."
      end
      table.insert(formatted_cols, string.format("%-" .. width .. "s", col_str))
    end
  end
  return table.concat(formatted_cols, COLUMN_SEPARATOR)
end

return M
