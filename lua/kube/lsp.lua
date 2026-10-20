---In-process language server for kube buffers, so that LSP keymaps and pickers work on them:
---hover = describe, definition = what the cell refers to (see `kube.navigation`),
---document symbols = the resources, code actions = `kube.operations` (on a range: bulk operations).
local kubectl = require("kubectl")
local navigation = require("kube.navigation")
local operations = require("kube.operations")
local utils = require("kube.utils")

local M = {}

M.NAME = "kube"

local EXECUTE_OPERATION = "kube.operation"

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
        -- Buffers are rendered by kube.nvim, the server never needs their text
        textDocumentSync = 0,
        hoverProvider = true,
        definitionProvider = true,
        documentSymbolProvider = true,
        codeActionProvider = true,
        executeCommandProvider = { commands = { EXECUTE_OPERATION } },
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
    local operation = params.command == EXECUTE_OPERATION and offered[params.arguments[1]]
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

---Attach the server to a kube buffer.
---@param buf integer
function M.attach(buf)
  vim.lsp.start({ name = M.NAME, cmd = M.server }, { bufnr = buf })
end

return M
