local M = {}

local highlights = {
    KubePending = { fg = "#FFA500" },
    KubeRunning = { fg = "#00FF00" },
    KubeFailed = { fg = "#FF0000" },
    KubeSucceeded = { fg = "#00FFFF" },
    KubeUnknown = { fg = "#808080" },
    KubeHeader = { bold = true, underline = true },
}

function M.render(headers, rows, resource_type, namespace)
    local buf_name = string.format("kube://%s/%s", namespace or "default", resource_type)
    local buf = vim.api.nvim_create_buf(false, true)

    local existing_buf = vim.fn.bufnr(buf_name)
    if existing_buf ~= -1 then
        vim.api.nvim_buf_delete(existing_buf, {force = true})
    end
    vim.api.nvim_buf_set_name(buf, buf_name)
    
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_set_current_buf(buf)
    
    for group, colors in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, colors)
    end
    
    local lines, highlights_to_apply = M.format_table(headers, rows)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    for _, hl in ipairs(highlights_to_apply) do
        vim.api.nvim_buf_add_highlight(buf, -1, hl.highlight, hl.row_idx, 0, -1)
    end
    
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

function M.format_table(headers, rows)
    local col_widths = {}
    for i, header in ipairs(headers) do
        col_widths[i] = #header
        for _, row in ipairs(rows) do
            col_widths[i] = math.max(col_widths[i], #(row[i] or ""))
        end
    end
    
    local lines = {M.format_row(headers, col_widths)}
    local highlights_to_apply = {
        { row_idx = 0, highlight = "KubeHeader" }
    }
    
    for row_idx, row in ipairs(rows) do
        table.insert(lines, M.format_row(row, col_widths))
        if row.highlight then
            table.insert(highlights_to_apply, {
                row_idx = row_idx,
                highlight = row.highlight
            })
        end
    end
    
    return lines, highlights_to_apply
end

function M.format_row(row, col_widths)
    local formatted_cols = {}
    for i, col in ipairs(row) do
        if i <= #col_widths then
            table.insert(formatted_cols, string.format("%-" .. col_widths[i] .. "s", col or ""))
        end
    end
    return table.concat(formatted_cols, "  ")
end

return M 