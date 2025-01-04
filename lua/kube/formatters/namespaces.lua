local base = require('kube.formatters.base')

local M = {}

M.headers = {
    "NAME",
    "STATUS",
    "AGE"
}

function M.format(data)
    local rows = {}
    
    for _, item in ipairs(data.items) do
        table.insert(rows, {
            item.metadata.name,
            item.status.phase or "Unknown",
            base.calculate_age(item.metadata.creationTimestamp),
        })
    end

    return rows
end

return M 