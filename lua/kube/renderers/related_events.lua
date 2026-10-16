local formatters = require("kube.formatters")
local kubectl = require("kubectl")

---The events of a workload or service and of the pods / replica sets it selects, for
---`kube://.../events?for={type}/{name}`: field selectors only match a single object.
---@type Renderer
local M = {}

---The label selector of a workload (`spec.selector.matchLabels`) or service (`spec.selector`).
---@param object table
---@return string|nil `key=value,...`
local function label_selector(object)
  local selector = object.spec and object.spec.selector
  if type(selector) ~= "table" then
    return nil
  end
  if selector.matchLabels or selector.matchExpressions then
    selector = selector.matchLabels or {}
  end
  local labels = {}
  for key, value in pairs(selector) do
    table.insert(labels, string.format("%s=%s", key, value))
  end
  table.sort(labels)
  return #labels > 0 and table.concat(labels, ",") or nil
end

---@param buffer KubeBuffer
---@param job vim.SystemObj|nil
local function track(buffer, job)
  if job then
    buffer.jobs[job.pid] = job
    -- Keep the buffer loading until the last call of the chain
    buffer.loading_job = job
  end
end

---@param buffer KubeBuffer
---@param involved table<string, true> `Kind/name` of the objects to show the events of
local function load_events(buffer, involved)
  track(
    buffer,
    kubectl.get(buffer.context, "events", nil, buffer.namespace, nil, function(result)
      if not result or not vim.api.nvim_buf_is_valid(buffer.buf_nr) then
        return
      end
      local events = vim.tbl_filter(function(event)
        local object = event.involvedObject or {}
        return involved[string.format("%s/%s", object.kind, object.name)] == true
      end, vim.json.decode(result).items)
      require("kube.renderers.resources").render(buffer, formatters.events, { items = events })
    end, buffer:on_error())
  )
end

function M.load(buffer)
  local resource_type, name = buffer.params["for"]:match("^(.-)/(.+)$")
  return kubectl.get(buffer.context, resource_type, name, buffer.namespace, nil, function(result)
    if not result or not vim.api.nvim_buf_is_valid(buffer.buf_nr) then
      return
    end
    local object = vim.json.decode(result)
    local involved = { [string.format("%s/%s", object.kind, name)] = true }
    local selector = label_selector(object)
    if not selector then
      load_events(buffer, involved)
      return
    end

    track(
      buffer,
      kubectl.get(buffer.context, "pods,replicasets", nil, buffer.namespace, { selector = selector }, function(owned)
        if not owned then
          return
        end
        for _, item in ipairs(vim.json.decode(owned).items) do
          involved[string.format("%s/%s", item.kind, item.metadata.name)] = true
        end
        load_events(buffer, involved)
      end, buffer:on_error())
    )
  end, buffer:on_error())
end

return M
