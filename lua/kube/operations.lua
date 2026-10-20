---Operations on the resources of buffer rows, offered as code actions.
local actions = require("kube.actions")
local confirm = require("kube.apply").confirm
local kubectl = require("kubectl")
local utils = require("kube.utils")

local M = {}

---@class KubeOperation
---@field title string
---@field run fun()

local LOGS = { Pod = true, Deployment = true, StatefulSet = true, DaemonSet = true, ReplicaSet = true, Job = true }
local SCALABLE = { Deployment = true, StatefulSet = true, ReplicaSet = true }
local ROLLOUT = { Deployment = true, StatefulSet = true, DaemonSet = true }
local RELATED_EVENTS =
  { Deployment = true, StatefulSet = true, DaemonSet = true, ReplicaSet = true, Job = true, Service = true }

---@param resources table[]
---@return string
local function describe_targets(resources)
  local names = vim.tbl_map(function(resource)
    return string.format("%s/%s", utils.resource_type(resource), resource.metadata.name)
  end, resources)
  if #names > 3 then
    return string.format("%s and %d more", table.concat(vim.list_slice(names, 1, 3), ", "), #names - 3)
  end
  return table.concat(names, ", ")
end

---Run `fn` for each resource and call `done` once all finished.
---@param resources table[]
---@param fn fun(resource: table, finished: fun())
---@param done fun()
local function each(resources, fn, done)
  local remaining = #resources
  for _, resource in ipairs(resources) do
    fn(resource, function()
      remaining = remaining - 1
      if remaining == 0 then
        done()
      end
    end)
  end
end

---Run a kubectl operation on every resource, then reload the buffer.
---@param kbuf KubeBuffer
---@param resources table[]
---@param call fun(resource: table, callback: fun(data: string|nil), on_error: fun(err: string))
local function run_kubectl(kbuf, resources, call)
  each(resources, function(resource, finished)
    call(resource, function(result)
      if result then
        vim.notify(vim.trim(result))
      end
      finished()
    end, function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
  end, function()
    kbuf:load()
  end)
end

---@param kbuf KubeBuffer
---@param resources table[]
---@param verb string
---@param call fun(resource: table, callback: fun(data: string|nil), on_error: fun(err: string))
local function confirmed(kbuf, resources, verb, call)
  confirm(string.format("%s %s (context: %s)?", verb, describe_targets(resources), kbuf.context), function(yes)
    if yes then
      run_kubectl(kbuf, resources, call)
    end
  end)
end

---Operations on a container of the buffer's resource: a row of a pod's containers buffer, or a
---container of the YAML of a pod or a workload.
---@param kbuf KubeBuffer
---@param container table
---@return KubeOperation[]
function M.for_container(kbuf, container)
  local function logs(params)
    utils.open({
      context = kbuf.context,
      namespace = kbuf.namespace,
      kind = kbuf.resource_kind,
      name = kbuf.resource_name,
      subresource = "logs",
      params = vim.tbl_extend("force", { container = container.name }, params),
    })
  end
  local container_actions = actions.containers
  return {
    {
      title = "Show logs",
      run = function()
        logs({})
      end,
    },
    {
      title = "Follow logs",
      run = function()
        logs({ follow = true })
      end,
    },
    {
      title = "Show logs of the previous instance",
      run = function()
        logs({ previous = true })
      end,
    },
    {
      title = "Exec",
      run = function()
        container_actions.exec(kbuf, container)
      end,
    },
    {
      title = "Forward port",
      run = function()
        container_actions.forward_port(kbuf, container)
      end,
    },
  }
end

---Operations on a resource type of the `api-resources` buffer.
---@param kbuf KubeBuffer
---@param type table
---@return KubeOperation[]
local function api_resource_operations(kbuf, type)
  local namespace = type.namespaced and kbuf.namespace or nil
  local operations = {
    {
      title = "List",
      run = function()
        vim.cmd.edit(vim.fn.fnameescape(require("kube.navigation").api_resource_target(kbuf, type)))
      end,
    },
  }
  if namespace and namespace ~= "all" then
    table.insert(operations, {
      title = "List in all namespaces",
      run = function()
        utils.open({ context = kbuf.context, kind = type.name })
      end,
    })
  end
  table.insert(operations, {
    title = "Show events",
    run = function()
      utils.open({
        context = kbuf.context,
        namespace = namespace,
        kind = "events",
        params = { ["field-selector"] = "involvedObject.kind=" .. type.object_kind },
      })
    end,
  })
  return operations
end

---Operations on port forward rows, of a resource or of `kube://portforwards`.
---@param kbuf KubeBuffer
---@param forwards table[]
---@return KubeOperation[]
local function portforward_operations(kbuf, forwards)
  local operations = {}
  if #forwards == 1 then
    local forward = forwards[1]
    local portforward = forward.portforward
    table.insert(operations, {
      title = "Open in browser",
      run = function()
        vim.ui.open(string.format("http://localhost:%d", forward.local_port))
      end,
    })
    table.insert(operations, {
      title = string.format("Go to %s/%s", portforward.resource_type, portforward.name),
      run = function()
        utils.open({
          context = portforward.context,
          namespace = portforward.namespace,
          kind = portforward.resource_type,
          name = portforward.name,
          params = { output = "yaml" },
        })
      end,
    })
  end

  local ports = vim.tbl_map(function(forward)
    return tostring(forward.local_port)
  end, forwards)
  table.insert(operations, {
    title = #forwards == 1 and "Stop" or string.format("Stop %d port forwards", #forwards),
    run = function()
      confirm(string.format("Stop the port forwards of local ports %s?", table.concat(ports, ", ")), function(yes)
        if not yes then
          return
        end
        for _, forward in ipairs(forwards) do
          kubectl.kill(forward.portforward.job)
          _G.portforwards[forward.id][forward.local_port] = nil
        end
        kbuf:load()
      end)
    end,
  })
  return operations
end

---@param kbuf KubeBuffer
---@param resource table
---@return KubeOperation[]
local function single_operations(kbuf, resource)
  local kind = resource.kind
  local kind_actions = actions[kind:lower()]
  local helpers = require("kube.actions.helpers")
  local operations = {
    {
      title = "Open",
      run = function()
        kind_actions.drill_down_resource(kbuf, resource)
      end,
    },
    {
      title = "Describe",
      run = function()
        helpers.open_resource(kbuf, resource)
      end,
    },
    {
      title = "Go to YAML",
      run = function()
        helpers.open_resource(kbuf, resource, nil, { output = "yaml" })
      end,
    },
    {
      title = "Show events",
      run = function()
        -- Workloads and services: also the events of the pods they select, see renderers.related_events
        local params = RELATED_EVENTS[kind]
            and { ["for"] = utils.resource_type(resource) .. "/" .. resource.metadata.name }
          or {
            ["field-selector"] = string.format(
              "involvedObject.kind=%s,involvedObject.name=%s",
              kind,
              resource.metadata.name
            ),
          }
        utils.open({
          context = kbuf.context,
          namespace = resource.metadata.namespace,
          kind = "events",
          params = params,
        })
      end,
    },
  }

  local function add(title, run)
    table.insert(operations, { title = title, run = run })
  end

  if LOGS[kind] then
    local function logs(params)
      return function()
        helpers.open_resource(kbuf, resource, "logs", params)
      end
    end
    add("Show logs", logs(nil))
    add("Follow logs", logs({ follow = true }))
    add("Show logs of all containers", logs({ ["all-containers"] = true }))
    if kind == "Pod" then
      add("Show logs of the previous instance", logs({ previous = true }))
    end
    add("Show logs since…", function()
      vim.ui.input({ prompt = "Since (e.g. 30s, 5m, 1h): ", default = "1h" }, function(since)
        if since and since ~= "" then
          logs({ since = since })()
        end
      end)
    end)
  end

  for _, action in ipairs({
    { "exec", "Exec" },
    { "forward_port", "Forward port" },
    { "port_forward", "Show port forwards" },
    { "set_image", "Set image" },
  }) do
    if kind_actions[action[1]] then
      add(action[2], function()
        kind_actions[action[1]](kbuf, resource)
      end)
    end
  end

  if ROLLOUT[kind] then
    add("Undo rollout", function()
      confirmed(kbuf, { resource }, "Undo the rollout of", function(r, callback, on_error)
        kubectl.rollout(
          kbuf.context,
          "undo",
          utils.resource_type(r),
          r.metadata.name,
          r.metadata.namespace,
          callback,
          on_error
        )
      end)
    end)
    add("Rollout history", function()
      helpers.open_resource(kbuf, resource, "history")
    end)
  end

  if kind == "Pod" then
    add("Debug (ephemeral container)", function()
      require("kube.utils.exec").prompt_debug(kbuf.context, resource)
    end)
  end

  if kind == "CronJob" then
    add("Trigger now", function()
      -- Job names are at most 63 characters, as they are label values
      local job = string.format("%s-manual-%d", resource.metadata.name:sub(1, 45), os.time())
      confirmed(kbuf, { resource }, "Trigger", function(r, callback, on_error)
        kubectl.create_job(kbuf.context, r.metadata.name, r.metadata.namespace, job, callback, on_error)
      end)
    end)
  end

  if kind == "Secret" then
    add("Decode secret", function()
      helpers.open_resource(kbuf, resource, "data")
    end)
  end

  return operations
end

---Operations that apply to all the resources at once.
---@param kbuf KubeBuffer
---@param resources table[]
---@return KubeOperation[]
local function bulk_operations(kbuf, resources)
  local operations = {}
  local function all(set)
    for _, resource in ipairs(resources) do
      if not set[resource.kind] then
        return false
      end
    end
    return true
  end

  if all(SCALABLE) then
    table.insert(operations, {
      title = "Scale…",
      run = function()
        local current = resources[1].spec and resources[1].spec.replicas or 1
        vim.ui.input({ prompt = "Replicas: ", default = tostring(current) }, function(input)
          local replicas = require("kube.edits").parse_replicas(input)
          if not replicas then
            if input then
              vim.notify("Invalid number of replicas: " .. input, vim.log.levels.ERROR)
            end
            return
          end
          run_kubectl(kbuf, resources, function(r, callback, on_error)
            kubectl.scale(
              kbuf.context,
              utils.resource_type(r),
              r.metadata.name,
              r.metadata.namespace,
              replicas,
              callback,
              on_error
            )
          end)
        end)
      end,
    })
  end

  if all(ROLLOUT) then
    table.insert(operations, {
      title = "Restart",
      run = function()
        confirmed(kbuf, resources, "Restart", function(r, callback, on_error)
          kubectl.rollout(
            kbuf.context,
            "restart",
            utils.resource_type(r),
            r.metadata.name,
            r.metadata.namespace,
            callback,
            on_error
          )
        end)
      end,
    })
  end

  if all({ Node = true }) then
    for _, verb in ipairs({ "cordon", "uncordon", "drain" }) do
      table.insert(operations, {
        title = verb:sub(1, 1):upper() .. verb:sub(2),
        run = function()
          local call = function(r, callback, on_error)
            kubectl.node(kbuf.context, verb, r.metadata.name, callback, on_error)
          end
          if verb == "drain" then
            confirmed(kbuf, resources, "Drain", call)
          else
            run_kubectl(kbuf, resources, call)
          end
        end,
      })
    end
  end

  table.insert(operations, {
    title = "Delete",
    run = function()
      confirmed(kbuf, resources, "Delete", function(r, callback, on_error)
        kubectl.delete(kbuf.context, utils.resource_type(r), r.metadata.name, r.metadata.namespace, callback, on_error)
      end)
    end,
  })

  return operations
end

---The operations for the items of the given buffer rows.
---@param kbuf KubeBuffer
---@param items table[]
---@return KubeOperation[]
function M.for_items(kbuf, items)
  if #items == 0 then
    return {}
  end

  if kbuf.subresource_kind == "containers" then
    return #items == 1 and M.for_container(kbuf, items[1]) or {}
  end
  if kbuf.resource_kind == "api-resources" then
    return #items == 1 and api_resource_operations(kbuf, items[1]) or {}
  end
  if kbuf.resource_kind == "portforwards" or kbuf.subresource_kind == "portforward" then
    return portforward_operations(kbuf, items)
  end

  local resources = vim.tbl_filter(function(item)
    return item.metadata ~= nil and item.kind ~= nil
  end, items)
  if #resources ~= #items then
    return {}
  end

  local operations = #resources == 1 and single_operations(kbuf, resources[1]) or {}
  if #resources > 1 then
    -- Name the targets in bulk operations
    for _, operation in ipairs(bulk_operations(kbuf, resources)) do
      operation.title = string.format("%s %d resources", operation.title:gsub("…$", ""), #resources)
      table.insert(operations, operation)
    end
    return operations
  end
  return vim.list_extend(operations, bulk_operations(kbuf, resources))
end

---The items of the rows in [first, last] (0-indexed, inclusive).
---@param kbuf KubeBuffer
---@param first integer
---@param last integer
---@return table[]
function M.items_in_rows(kbuf, first, last)
  local items = {}
  local marks = vim.api.nvim_buf_get_extmarks(
    kbuf.buf_nr,
    require("kube.constants").KUBE_NAMESPACE,
    { first, 0 },
    { last, -1 },
    {}
  )
  for _, mark in ipairs(marks) do
    local marked_line = kbuf.mark_mappings[mark[1]]
    if marked_line then
      table.insert(items, marked_line.item)
    end
  end
  return items
end

return M
