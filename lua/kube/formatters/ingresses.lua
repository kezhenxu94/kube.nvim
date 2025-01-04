local base = require('kube.formatters.base')

local M = {}

M.headers = {
    "NAME",
    "CLASS",
    "HOSTS",
    "ADDRESS",
    "PORTS",
    "AGE"
}

function M.format(data)
    local rows = {}
    for _, item in ipairs(data.items) do
        local hosts = {}
        for _, rule in ipairs(item.spec.rules or {}) do
            table.insert(hosts, rule.host or "*")
        end

        table.insert(rows, {
            item.metadata.name,
            item.spec.ingressClassName or "<none>",
            table.concat(hosts, ","),
            item.status.loadBalancer and item.status.loadBalancer.ingress and
                item.status.loadBalancer.ingress[1].ip or "<pending>",
            "80",  -- Most common case, you might want to make this more dynamic
            base.calculate_age(item.metadata.creationTimestamp),
        })
    end
    return rows
end

return M 