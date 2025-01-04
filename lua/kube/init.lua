local kubectl = require('kubectl')

local M = {}

-- Format data into table rows
local function format_table(data, resource_type)
    local rows = {}
    local headers = {"NAME", "READY", "STATUS", "RESTARTS", "IP", "NODE", "AGE"}
    if resource_type == "pods" then
        for _, pod in ipairs(data.items) do
            local name = pod.metadata.name
            local status = pod.status.phase
            local created = pod.metadata.creationTimestamp
            
            local ready_count = 0
            local container_count = #pod.spec.containers
            if pod.status.containerStatuses then
                for _, container in ipairs(pod.status.containerStatuses) do
                    if container.ready then ready_count = ready_count + 1 end
                end
            end
            local ready = string.format("%d/%d", ready_count, container_count)
            
            local restarts = 0
            if pod.status.containerStatuses then
                for _, container in ipairs(pod.status.containerStatuses) do
                    restarts = restarts + container.restartCount
                end
            end
            
            local ip = pod.status.podIP or ""
            local node = pod.spec.nodeName or ""
            local year = tonumber(created:sub(1,4))
            local month = tonumber(created:sub(6,7))
            local day = tonumber(created:sub(9,10))
            local hour = tonumber(created:sub(12,13))
            local min = tonumber(created:sub(15,16))
            local sec = tonumber(created:sub(18,19))
            
            local creation_time_utc = os.time({
                year = year,
                month = month,
                day = day,
                hour = hour,
                min = min,
                sec = sec,
                isdst = false
            })
            
            local creation_time = creation_time_utc - os.difftime(os.time(os.date("!*t")), os.time(os.date("*t")))
            
            local now = os.time()
            
            local age_secs = os.difftime(now, creation_time)
            local age
            
            if age_secs < 60 then
                age = string.format("%ds", age_secs)
            elseif age_secs < 3600 then
                age = string.format("%dm", math.floor(age_secs/60))
            elseif age_secs < 86400 then
                age = string.format("%dh", math.floor(age_secs/3600))
            else
                age = string.format("%dd", math.floor(age_secs/86400))
            end
            
            table.insert(rows, {
                name,
                ready,
                status,
                tostring(restarts),
                ip,
                node,
                age,
                highlight = "Kube" .. status
            })
        end
    end
    
    return headers, rows
end

-- Render the table in a buffer
local function render_table(headers, rows, resource_type, namespace)
    -- Create named buffer
    local buf_name = string.format("kube://%s/%s", namespace or "default", resource_type)
    local buf = vim.api.nvim_create_buf(false, true)

    local existing_buf = vim.fn.bufnr(buf_name)
    if existing_buf ~= -1 then
        vim.api.nvim_buf_delete(existing_buf, {force = true})
    end
    vim.api.nvim_buf_set_name(buf, buf_name)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    
    -- Switch to the buffer in the current window
    vim.api.nvim_set_current_buf(buf)
    
    -- Define highlight groups if they don't exist
    local highlights = {
        KubePending = { fg = "#FFA500" },  -- Orange
        KubeRunning = { fg = "#00FF00" },  -- Green
        KubeFailed = { fg = "#FF0000" },   -- Red
        KubeSucceeded = { fg = "#00FFFF" }, -- Cyan
        KubeUnknown = { fg = "#808080" },  -- Gray
    }

    for group, colors in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, colors)
    end
    
    -- Calculate column widths
    local col_widths = {}
    for i, header in ipairs(headers) do
        col_widths[i] = #header
        for _, row in ipairs(rows) do
            col_widths[i] = math.max(col_widths[i], #(row[i] or ""))
        end
    end
    
    -- Render headers
    local header_line = {}
    for i, header in ipairs(headers) do
        table.insert(header_line, string.format("%-" .. col_widths[i] .. "s", header))
    end
    local lines = {table.concat(header_line, "  ")}
    
    -- Track line numbers for highlighting
    local highlights_to_apply = {}
    
    -- Render rows
    for row_idx, row in ipairs(rows) do
        local formatted_cols = {}
        for i, col in ipairs(row) do
            if i <= #headers then
                table.insert(formatted_cols, string.format("%-" .. col_widths[i] .. "s", col or ""))
            end
        end
        local line = table.concat(formatted_cols, "  ")
        table.insert(lines, line)
        
        -- Store highlight information if row has highlight property
        if row.highlight then
            table.insert(highlights_to_apply, {
                row_idx = row_idx,
                highlight = row.highlight
            })
        end
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Apply highlights
    for _, hl in ipairs(highlights_to_apply) do
        vim.api.nvim_buf_add_highlight(buf, -1, hl.highlight, hl.row_idx, 0, -1)
    end
    
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

-- Main function to display resources
function M.show_resources(resource_type, namespace)
    local result = kubectl.get(resource_type, nil, namespace)
    local data = vim.fn.json_decode(result)
    
    local headers, rows = format_table(data, resource_type)
    render_table(headers, rows, resource_type, namespace)
end

return M
