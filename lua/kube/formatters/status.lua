---Statuses of pods and containers, as kubectl shows them.
local M = {}

local PENDING = { Pending = true, Waiting = true, ContainerCreating = true, PodInitializing = true }

---The highlight group of a status.
---@param status string
---@return string
function M.highlight(status)
  if status == "Running" then
    return "KubeRunning"
  elseif status == "Completed" or status == "Succeeded" then
    return "KubeSucceeded"
  elseif status == "Unknown" then
    return "KubeUnknown"
  elseif status == "Terminating" or PENDING[status] or status:match("^Init:%d") then
    return "KubePending"
  end
  -- CrashLoopBackOff, ImagePullBackOff, Error, OOMKilled, Evicted, Init:Error, ...
  return "KubeFailed"
end

---@param terminated table `state.terminated` of a container status
---@return string
function M.terminated_reason(terminated)
  if type(terminated.reason) == "string" and terminated.reason ~= "" then
    return terminated.reason
  end
  if (terminated.signal or 0) ~= 0 then
    return "Signal:" .. terminated.signal
  end
  return "ExitCode:" .. (terminated.exitCode or 0)
end

---The status of a container and its highlight group.
---@param container_status table|nil
---@return string status
---@return string highlight
function M.container(container_status)
  local state = container_status and container_status.state or {}
  if state.running then
    return "Running", "KubeRunning"
  elseif state.waiting then
    local reason = type(state.waiting.reason) == "string" and state.waiting.reason or "Waiting"
    return reason, M.highlight(reason)
  elseif state.terminated then
    return M.terminated_reason(state.terminated), state.terminated.exitCode == 0 and "KubeSucceeded" or "KubeFailed"
  end
  return "Unknown", "KubeUnknown"
end

---The status of a pod, like the STATUS column of `kubectl get pods`.
---@param pod table
---@return string
function M.pod(pod)
  local status = pod.status or {}
  local reason = type(status.reason) == "string" and status.reason or status.phase or "Unknown"

  local init_specs = {}
  for _, container in ipairs(pod.spec.initContainers or {}) do
    init_specs[container.name] = container
  end

  local initializing = false
  for i, container_status in ipairs(status.initContainerStatuses or {}) do
    local state = container_status.state or {}
    local spec = init_specs[container_status.name] or {}
    if state.terminated and state.terminated.exitCode == 0 then
      -- Done
    elseif spec.restartPolicy == "Always" and container_status.started then
      -- A started sidecar does not block the pod
    else
      initializing = true
      if state.terminated then
        reason = "Init:" .. M.terminated_reason(state.terminated)
      elseif state.waiting and type(state.waiting.reason) == "string" and state.waiting.reason ~= "PodInitializing" then
        reason = "Init:" .. state.waiting.reason
      else
        reason = string.format("Init:%d/%d", i - 1, #(pod.spec.initContainers or {}))
      end
      break
    end
  end

  if not initializing then
    local running = false
    local container_statuses = status.containerStatuses or {}
    -- Backwards, so that the first container with a reason wins
    for i = #container_statuses, 1, -1 do
      local state = container_statuses[i].state or {}
      if state.waiting and type(state.waiting.reason) == "string" and state.waiting.reason ~= "" then
        reason = state.waiting.reason
      elseif state.terminated then
        reason = M.terminated_reason(state.terminated)
      elseif state.running and container_statuses[i].ready then
        running = true
      end
    end
    if reason == "Completed" and running then
      reason = "Running"
    end
  end

  if type(pod.metadata.deletionTimestamp) == "string" then
    return "Terminating"
  end
  return reason
end

return M
