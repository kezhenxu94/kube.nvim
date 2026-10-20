---In-process language server for kube buffers, so that LSP keymaps and pickers work on them:
---hover = describe, definition = what the cell refers to (see `kube.navigation`),
---document symbols = the resources, code actions = `kube.operations` (on a range: bulk operations),
---selection ranges = cell -> row -> list, for the default |an| / |in|, declaration = the owner,
---references = the pods using the resource, code lenses = the operations on the containers of a YAML.
local constants = require("kube.constants")
local kubectl = require("kubectl")
local navigation = require("kube.navigation")
local operations = require("kube.operations")
local pods_using = require("kube.renderers.pods_using")
local utils = require("kube.utils")

local M = {}

M.NAME = "kube"

local EXECUTE_OPERATION = "kube.operation"
local CONTAINER_OPERATION = "kube.container"

-- The operations of `operations.for_container` offered as code lenses
local CONTAINER_LENSES = { "Show logs", "Follow logs", "Exec" }
-- Kinds whose containers have logs and shells
local CONTAINER_KINDS =
  { Pod = true, Deployment = true, StatefulSet = true, DaemonSet = true, ReplicaSet = true, Job = true }

---@type vim.lsp.rpc.Dispatchers|nil
local client_dispatchers

---Operations of the last code action request, by id.
---@type table<integer, KubeOperation>
local offered = {}

---@param uri string
---@return KubeBuffer|nil
local function kube_buffer(uri)
  return _G.kube_buffers[vim.uri_to_bufnr(uri)]
end

---@param line integer
---@return lsp.Range
local function line_range(line)
  return { start = { line = line, character = 0 }, ["end"] = { line = line, character = 0 } }
end

---@param start_line integer
---@param start_col integer
---@param end_line integer
---@param end_col integer
---@return lsp.Range
local function range(start_line, start_col, end_line, end_col)
  return { start = { line = start_line, character = start_col }, ["end"] = { line = end_line, character = end_col } }
end

---The cell at `pos`, from the start of its text to the end, as byte columns.
---@param kbuf KubeBuffer
---@param pos integer[] (0,0)-indexed position
---@return lsp.Range|nil
local function cell_range(kbuf, pos)
  local marks = vim.api.nvim_buf_get_extmarks(
    kbuf.buf_nr,
    constants.KUBE_COLUMN_NAMESPACE,
    pos,
    pos,
    { overlap = true, details = true }
  )
  for _, mark in ipairs(marks) do
    local row, col, details = mark[2], mark[3], mark[4]
    -- Overlapping also returns the cell ending right before `pos`
    if kbuf.mark_columns[mark[1]] and row == details.end_row and col <= pos[2] and pos[2] < details.end_col then
      local text = vim.api.nvim_buf_get_text(kbuf.buf_nr, row, col, row, details.end_col, {})[1]
      -- Cells are padded to the width of their column
      local first, last = text:find("%S"), text:find("%S%s*$")
      if first then
        return range(row, col + first - 1, row, col + last)
      end
    end
  end
  return nil
end

---The resource of the row at `line`, or of the buffer of a single resource (YAML, describe).
---@param kbuf KubeBuffer
---@param line integer
---@param callback fun(resource: table|nil)
local function resource_at(kbuf, line, callback)
  if not kbuf.resource_name or kbuf.subresource_kind then
    local item = operations.items_in_rows(kbuf, line, line)[1]
    callback(item and item.metadata and item or nil)
    return
  end
  kubectl.get(kbuf.context, kbuf.resource_kind, kbuf.resource_name, kbuf.namespace, nil, function(result)
    callback(result and vim.json.decode(result) or nil)
  end)
end

---The containers of the YAML of a pod or a workload, as kubectl outputs it.
---@param lines string[]
---@return {name: string, line: integer}[] With the 0-indexed line of the container's item
local function yaml_containers(lines)
  local containers = {}
  -- The indent of the `containers:` key being read, its items start with `{indent}- `
  local indent, item
  for i, line in ipairs(lines) do
    if indent then
      local prefix = line:sub(1, #indent + 2)
      if prefix == indent .. "- " then
        item = i - 1
      elseif prefix ~= indent .. "  " then
        indent = nil
      end
    end
    if indent then
      local name = line:sub(#indent + 3):match("^name: (%S+)$")
      if name then
        table.insert(containers, { name = name, line = item })
      end
    else
      indent = line:match("^(%s*)containers:$")
    end
  end
  return containers
end

local progress_count = 0

---Report work done progress (`$/progress`) to the client, created by the server.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@param title string
---@return fun(message: string|nil) done Ends the progress
local function progress(dispatchers, title)
  progress_count = progress_count + 1
  local token = "kube.nvim/" .. progress_count
  local _, err = dispatchers.server_request("window/workDoneProgress/create", { token = token })
  if err then
    return function() end
  end
  dispatchers.notification("$/progress", { token = token, value = { kind = "begin", title = title } })
  return function(message)
    dispatchers.notification("$/progress", { token = token, value = { kind = "end", message = message } })
  end
end

---@type table<string, fun(params: table, reply: fun(err: lsp.ResponseError|nil, result: any), dispatchers: vim.lsp.rpc.Dispatchers)>
local handlers = {
  initialize = function(_, reply)
    reply(nil, {
      capabilities = {
        -- Columns are those of the extmarks, in bytes
        positionEncoding = "utf-8",
        -- Buffers are rendered by kube.nvim, the server never needs their text
        textDocumentSync = 0,
        hoverProvider = true,
        definitionProvider = true,
        documentSymbolProvider = true,
        codeActionProvider = true,
        selectionRangeProvider = true,
        declarationProvider = true,
        referencesProvider = true,
        codeLensProvider = { resolveProvider = false },
        executeCommandProvider = { commands = { EXECUTE_OPERATION, CONTAINER_OPERATION } },
      },
      serverInfo = { name = "kube.nvim" },
    })
  end,

  shutdown = function(_, reply)
    reply(nil, nil)
  end,

  ["textDocument/hover"] = function(params, reply, dispatchers)
    local kbuf = kube_buffer(params.textDocument.uri)
    local line = params.position.line
    local resource = kbuf and operations.items_in_rows(kbuf, line, line)[1]
    local title, run
    if resource and resource.kind == "APIResource" then
      -- A resource type: its documentation
      title = "Explaining " .. resource.name
      run = function(callback, on_error)
        kubectl.explain(kbuf.context, resource.name, callback, on_error)
      end
    elseif resource and resource.metadata and resource.kind then
      local resource_type = utils.resource_type(resource)
      title = string.format("Describing %s/%s", resource_type, resource.metadata.name)
      run = function(callback, on_error)
        kubectl.describe(
          kbuf.context,
          resource_type,
          resource.metadata.name,
          resource.metadata.namespace,
          callback,
          on_error
        )
      end
    else
      reply(nil, nil)
      return
    end

    -- The hover is only shown once kubectl answers: report the progress meanwhile
    local done = progress(dispatchers, title)
    run(function(result)
      done(not result and "Failed" or nil)
      reply(nil, result and { contents = { kind = "plaintext", value = vim.trim(result) } } or nil)
    end, function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
  end,

  ["textDocument/definition"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    local target = kbuf and navigation.tag_target(kbuf, { params.position.line, params.position.character })
    reply(nil, target and { uri = target, range = line_range(0) } or nil)
  end,

  ["textDocument/declaration"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    if not kbuf then
      reply(nil, nil)
      return
    end
    resource_at(kbuf, params.position.line, function(resource)
      local owners = resource and resource.metadata.ownerReferences or {}
      local owner = vim.iter(owners):find(function(ref)
        return ref.controller
      end) or owners[1]
      reply(nil, owner and {
        uri = utils.buf_name({
          context = kbuf.context,
          namespace = resource.metadata.namespace,
          kind = utils.resource_type(owner),
          name = owner.name,
          params = { output = "yaml" },
        }),
        range = line_range(0),
      } or nil)
    end)
  end,

  ["textDocument/references"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    if not kbuf then
      reply(nil, {})
      return
    end
    resource_at(kbuf, params.position.line, function(resource)
      local kind = resource and pods_using.KINDS[resource.kind]
      if not kind then
        reply(nil, {})
        return
      end
      -- The pods using it, as rows of a single list: the locations of separate pods would
      -- each be loaded by the client, for the text of the quickfix list
      local uri = utils.buf_name({
        context = kbuf.context,
        namespace = kind ~= "node" and resource.metadata.namespace or nil,
        kind = "pods",
        params = { using = kind .. "/" .. resource.metadata.name },
      })
      local buf = vim.fn.bufadd(uri)
      local loaded = vim.api.nvim_buf_is_loaded(buf)
      if not loaded then
        vim.fn.bufload(buf)
      end
      local target = _G.kube_buffers[buf]
      if not target then
        reply(nil, {})
        return
      end
      target:on_loaded(function()
        local locations = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, constants.KUBE_NAMESPACE, 0, -1, {})) do
          if target.mark_mappings[mark[1]] then
            table.insert(locations, { uri = uri, range = line_range(mark[2]) })
          end
        end
        reply(nil, locations)
      end)
      if loaded then
        target:load()
      end
    end)
  end,

  ["textDocument/codeLens"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    if not kbuf or not kbuf.resource_name or (kbuf.params or {}).output ~= "yaml" then
      reply(nil, {})
      return
    end
    local lines = vim.api.nvim_buf_get_lines(kbuf.buf_nr, 0, -1, false)
    local kind = vim
      .iter(lines)
      :map(function(line)
        return line:match("^kind: (%S+)$")
      end)
      :next()
    local lenses = {}
    if CONTAINER_KINDS[kind] then
      for _, container in ipairs(yaml_containers(lines)) do
        for _, title in ipairs(CONTAINER_LENSES) do
          table.insert(lenses, {
            range = line_range(container.line),
            command = {
              title = title,
              command = CONTAINER_OPERATION,
              arguments = { params.textDocument.uri, container.name, title },
            },
          })
        end
      end
    end
    reply(nil, lenses)
  end,

  ["textDocument/documentSymbol"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    local symbols = {}
    if kbuf then
      local last = vim.api.nvim_buf_line_count(kbuf.buf_nr) - 1
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(kbuf.buf_nr, require("kube.constants").KUBE_NAMESPACE, 0, -1, {}))
      do
        local marked_line = kbuf.mark_mappings[mark[1]]
        local item = marked_line and marked_line.item
        local name = item and (item.metadata and item.metadata.name or item.name)
        if name and mark[2] <= last then
          table.insert(symbols, {
            name = name,
            detail = item.metadata and item.metadata.namespace or nil,
            kind = vim.lsp.protocol.SymbolKind.Object,
            range = line_range(mark[2]),
            selectionRange = line_range(mark[2]),
          })
        end
      end
    end
    reply(nil, symbols)
  end,

  ["textDocument/selectionRange"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    if not kbuf then
      reply(nil, {})
      return
    end
    local lines = vim.api.nvim_buf_get_lines(kbuf.buf_nr, 0, -1, false)
    local list = { range = range(0, 0, #lines - 1, #lines[#lines]) }
    reply(
      nil,
      vim.tbl_map(function(position)
        local line = position.line
        local row = { range = range(line, 0, line, #(lines[line + 1] or "")), parent = list }
        local cell = cell_range(kbuf, { line, position.character })
        return cell and { range = cell, parent = row } or row
      end, params.positions)
    )
  end,

  ["textDocument/codeAction"] = function(params, reply)
    local kbuf = kube_buffer(params.textDocument.uri)
    if not kbuf then
      reply(nil, {})
      return
    end
    local first, last = params.range.start.line, params.range["end"].line
    -- A linewise range ends at the start of the next line
    if last > first and params.range["end"].character == 0 then
      last = last - 1
    end

    offered = {}
    local code_actions = {}
    for id, operation in ipairs(operations.for_items(kbuf, operations.items_in_rows(kbuf, first, last))) do
      offered[id] = operation
      table.insert(code_actions, {
        title = operation.title,
        command = { title = operation.title, command = EXECUTE_OPERATION, arguments = { id } },
      })
    end
    reply(nil, code_actions)
  end,

  ["workspace/executeCommand"] = function(params, reply)
    local operation
    if params.command == EXECUTE_OPERATION then
      operation = offered[params.arguments[1]]
    elseif params.command == CONTAINER_OPERATION then
      local uri, name, title = unpack(params.arguments)
      local kbuf = kube_buffer(uri)
      operation = kbuf
        and vim.iter(operations.for_container(kbuf, { name = name })):find(function(candidate)
          return candidate.title == title
        end)
    end
    reply(nil, nil)
    if operation then
      operation.run()
    end
  end,
}

---The in-process server, see `cmd` of `vim.lsp.ClientConfig`.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return table The RPC client (vim.lsp.rpc.PublicClient in 0.11, vim.lsp.rpc.Client later)
function M.server(dispatchers)
  client_dispatchers = dispatchers
  local closing = false
  local request_id = 0
  return {
    request = function(method, params, callback, notify_reply_callback)
      request_id = request_id + 1
      local id = request_id
      -- The client registers the request after this returns, so always reply later
      local function reply(err, result)
        vim.schedule(function()
          callback(err, result)
          if notify_reply_callback then
            notify_reply_callback(id)
          end
        end)
      end
      local handler = handlers[method]
      if handler then
        handler(params, reply, dispatchers)
      else
        reply({ code = vim.lsp.protocol.ErrorCodes.MethodNotFound, message = "Not supported: " .. method }, nil)
      end
      return true, id
    end,
    notify = function(method)
      if method == "exit" then
        dispatchers.on_exit(0, 15)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
    end,
  }
end

---Ask the client for the code lenses again, once a YAML buffer is loaded.
function M.refresh_code_lenses()
  if client_dispatchers then
    client_dispatchers.server_request("workspace/codeLens/refresh", nil)
  end
end

---Attach the server to a kube buffer.
---@param buf integer
function M.attach(buf)
  vim.lsp.start({ name = M.NAME, cmd = M.server }, { bufnr = buf })
end

return M
