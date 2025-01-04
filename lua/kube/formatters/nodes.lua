local base = require('kube.formatters.base')

local M = {}

M.headers = {
    "NAME",
    "STATUS",
    "ROLES",
    "AGE",
    "VERSION"
}

function M.format(data)
    local rows = {}
    for _, item in ipairs(data.items) do
        local roles = {}
        for label, value in pairs(item.metadata.labels or {}) do
            if label:match("^node%-role.kubernetes.io/") then
                table.insert(roles, label:match("node%-role.kubernetes.io/(.+)"))
            end
        end

        table.insert(rows, {
            item.metadata.name,
            table.concat(item.status.conditions[#item.status.conditions].type, ","),
            table.concat(roles, ","),
            base.calculate_age(item.metadata.creationTimestamp),
            item.status.nodeInfo.kubeletVersion
        })
    end
    return rows
end

return M 