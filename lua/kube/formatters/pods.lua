local base = require('kube.formatters.base')

local M = {}

M.headers = {"NAME", "READY", "STATUS", "RESTARTS", "IP", "NODE", "AGE"}

function M.format(data)
    local rows = {}
    for _, pod in ipairs(data.items) do
        local name = pod.metadata.name
        local status = pod.status.phase
        
        -- Calculate ready count
        local ready_count = 0
        local container_count = #pod.spec.containers
        if pod.status.containerStatuses then
            for _, container in ipairs(pod.status.containerStatuses) do
                if container.ready then ready_count = ready_count + 1 end
            end
        end
        local ready = string.format("%d/%d", ready_count, container_count)
        
        -- Calculate restarts
        local restarts = 0
        if pod.status.containerStatuses then
            for _, container in ipairs(pod.status.containerStatuses) do
                restarts = restarts + container.restartCount
            end
        end
        
        table.insert(rows, {
            name,
            ready,
            status,
            tostring(restarts),
            pod.status.podIP or "",
            pod.spec.nodeName or "",
            base.calculate_age(pod.metadata.creationTimestamp),
            highlight = "Kube" .. status
        })
    end
    return rows
end

return M 