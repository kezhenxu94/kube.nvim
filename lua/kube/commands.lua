local M = {}

---@class CommandBase
---@field parse fun(args: string[], opts: table): table Parse command arguments (and the user command opts) into parameters
---@field complete fun(arglead: string, args: string[]): string[] Provide completions for the command
local CommandBase = {}

---@class GetCommand : CommandBase
local GetCommand = {
  ---@param args string[]
  parse = function(args)
    local kind = table.remove(args, 1)
    local params = {}
    for _, arg in ipairs(args) do
      local key, value = arg:match("^([^=]+)=(.+)$")
      if key then
        params[key] = value
      end
    end
    return { kind, params }
  end,

  complete = function(arglead, args)
    if #args <= 1 then
      local kinds = require("kubectl").api_resources_sync()
      if arglead and arglead ~= "" then
        return vim.tbl_filter(function(kind)
          return vim.startswith(kind:lower(), arglead:lower())
        end, kinds)
      end
      return kinds
    end

    local params = { "namespace", "selector" }
    if arglead and arglead ~= "" then
      return vim.tbl_filter(function(param)
        return vim.startswith(param, arglead)
      end, params)
    end
    return params
  end,
}

---@class DeleteCommand : CommandBase
local DeleteCommand = {
  ---@param args string[]
  parse = function(args)
    local kind = table.remove(args, 1)
    local name = table.remove(args, 1)
    local params = {}
    for _, arg in ipairs(args) do
      local key, value = arg:match("^([^=]+)=(.+)$")
      if key then
        params[key] = value
      end
    end
    return { kind, name, params }
  end,

  complete = function(arglead, args)
    if #args <= 1 then
      -- Complete resource kinds
      local kinds = require("kubectl").api_resources_sync()
      if arglead and arglead ~= "" then
        return vim.tbl_filter(function(kind)
          return vim.startswith(kind:lower(), arglead:lower())
        end, kinds)
      end
      return kinds
    elseif #args == 2 then
      -- Without namespace=, :Kube delete deletes in the default namespace
      return vim.tbl_filter(function(name)
        return vim.startswith(name, arglead or "")
      end, require("kubectl").resource_names_sync(args[1], "default"))
    end

    -- Parameter completion
    local params = { "namespace", "selector" }
    if arglead and arglead ~= "" then
      return vim.tbl_filter(function(param)
        return vim.startswith(param, arglead)
      end, params)
    end
    return params
  end,
}

---@class ContextCommand : CommandBase
local ContextCommand = {
  parse = function(args)
    return { args[1] }
  end,

  complete = function(arglead, _)
    if arglead and arglead ~= "" then
      return vim.tbl_filter(function(context)
        return vim.startswith(context, arglead)
      end, require("kubectl").context_names_sync())
    end
    return require("kubectl").context_names_sync()
  end,
}

---Commands on the current buffer as a manifest; `:Kube! apply` skips the confirmation.
---@type CommandBase
local ManifestCommand = {
  parse = function(_, opts)
    return { opts.bang }
  end,

  complete = function()
    return {}
  end,
}

---@type CommandBase
local NoArgsCommand = {
  parse = function()
    return {}
  end,

  complete = function()
    return {}
  end,
}

M.command_handlers = {
  get = GetCommand,
  delete = DeleteCommand,
  context = ContextCommand,
  apply = ManifestCommand,
  diff = ManifestCommand,
  portforwards = NoArgsCommand,
}

function M.setup()
  vim.api.nvim_create_user_command("Kube", function(opts)
    local args = vim.split(opts.args, " ", { trimempty = true })
    local command = table.remove(args, 1)

    local handler = M.command_handlers[command]
    if not handler then
      vim.notify("No such command: " .. (command or ""), vim.log.levels.ERROR)
      return
    end

    local parsed = handler.parse(args, opts)
    M.commands[command](unpack(parsed))
  end, {
    nargs = "*",
    bang = true,
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, " ", { trimempty = false })
      table.remove(args, 1) -- Remove the command name "Kube"

      if #args <= 1 then
        local commands = vim.tbl_keys(M.commands)
        if arglead and arglead ~= "" then
          return vim.tbl_filter(function(cmd)
            return vim.startswith(cmd, arglead)
          end, commands)
        end
        return commands
      end

      local command = table.remove(args, 1)
      local handler = M.command_handlers[command]
      return handler and handler.complete(arglead, args) or {}
    end,
  })
end

M.commands = {
  get = function(...)
    require("kube").get(...)
  end,

  delete = function(...)
    require("kube").delete(...)
  end,

  context = function(...)
    require("kube").ctx(...)
  end,

  apply = function(force)
    require("kube").apply_buffer(force)
  end,

  diff = function()
    require("kube").diff_buffer()
  end,

  portforwards = function()
    vim.cmd.edit("kube://portforwards")
  end,
}

return M
