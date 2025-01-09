local constants = require("kube.constants")
local formatters = require("kube.formatters")
local log = require("kube.log")

local M = {}

---@param buffer KubeBuffer The buffer to render into
function M.load(buffer)
  local self = buffer
  local resource_kind = self.resource_kind
  local resource_name = self.resource_name
  local subresource_kind = self.subresource_kind
  local namespace = self.namespace
  local formatter = formatters[resource_kind]
  if subresource_kind and formatters[subresource_kind] then
    formatter = formatters[subresource_kind]
    log.debug("formatter for subresource found", subresource_kind, formatter)
  end

  log.debug("loading buffer", resource_kind, resource_name, namespace, subresource_kind)

  local headers = formatter.headers
  local kubectl = require("kubectl")
  local job = kubectl.get(resource_kind, resource_name, namespace, function(result)
    vim.schedule(function()
      vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_NAMESPACE, 0, -1)
      vim.api.nvim_buf_clear_namespace(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, 0, -1)

      if not result then
        log.debug("empty result", namespace, resource_kind, resource_name)
        return
      end

      local data = vim.fn.json_decode(result)
      buffer.data = data

      local rows = formatter.format(data)

      self:setup()

      local formatted_rows, col_widths = M.format_table(headers, rows)

      local lines = {}
      for _, row in ipairs(formatted_rows) do
        table.insert(lines, row.formatted)
      end
      vim.api.nvim_buf_set_lines(self.buf_nr, 0, -1, false, lines)

      for row_num, row in ipairs(formatted_rows) do
        vim.api.nvim_buf_add_highlight(self.buf_nr, -1, row.highlight or "KubeBody", row_num - 1, 0, -1)
        if row_num > 0 and row.raw then
          local mark_id = vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_NAMESPACE, row_num - 1, 0, {
            invalidate = true,
          })
          self.mark_mappings[mark_id] = {
            item = row.raw,
          }
        end

        local col_pos = 0
        for i, col_width in ipairs(col_widths) do
          local mark_id =
            vim.api.nvim_buf_set_extmark(self.buf_nr, constants.KUBE_COLUMN_NAMESPACE, row_num - 1, col_pos, {
              end_col = col_pos + col_width,
              invalidate = true,
            })
          log.debug("mark_id", mark_id, "col_pos", col_pos, "col_width", col_width)
          self.mark_columns[mark_id] = {
            item = row.raw,
            column = headers[i],
          }
          col_pos = col_pos + col_width
        end
      end

      vim.api.nvim_buf_set_option(buffer.buf_nr, "modified", false)
    end)
  end)

  if job then
    self.jobs[job.pid] = job
  end
end

---@class FormattedTableRow
---@field formatted string The formatted line with proper column spacing
---@field highlight string|nil The highlight group to apply to the row
---@field raw table The original row data
---@param headers string[] List of column headers
---@param rows FormattedRow[] List of row data
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

  local formatted_rows = {
    {
      formatted = M.align_row(headers, col_widths),
      highlight = "KubeHeader",
      raw = headers,
    },
  }

  for _, row in ipairs(rows) do
    table.insert(formatted_rows, {
      formatted = M.align_row(row.row, col_widths),
      highlight = row.row.highlight,
      raw = row.item,
    })
  end

  return formatted_rows, col_widths
end

---@param row FormattedRow List of columns
---@param col_widths number[] List of column widths
---@return string Formatted row string
function M.align_row(row, col_widths)
  local formatted_cols = {}
  for i, col in ipairs(row) do
    if i <= #col_widths then
      local width = math.min(99, col_widths[i])
      local col_str = col or ""
      if #col_str > width then
        col_str = col_str:sub(1, width - 3) .. "..."
      end
      table.insert(formatted_cols, string.format("%-" .. width .. "s", col_str))
    end
  end
  return table.concat(formatted_cols, "  ")
end

return M
