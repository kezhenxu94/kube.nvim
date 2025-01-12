local M = {}

---@class CommandBase
---@field parse fun(args: string[]): table Parse command arguments into parameters
---@field complete fun(arglead: string, args: string[]): string[] Provide completions for the command
local CommandBase = {}

---@class GetCommand : CommandBase
local GetCommand = {
  ---@param args string[]
  parse = function(args)
    local kind = table.remove(args, 1)
    local params = {}
    for _, arg in ipairs(args) do
      local key, value = arg:match("^(.+)=(.+)$")
      if key then
        params[key] = value
      end
    end
    return { kind, params }
  end,

  complete = function(arglead, args)
    local kinds = require("kubectl").api_resources_sync()
    if #args <= 1 then
      if arglead and arglead ~= "" then
        return vim.tbl_filter(function(kind)
          return vim.startswith(kind:lower(), arglead:lower())
        end, kinds)
      end
      return kinds
    end

    local params = { "namespace" }
    return params
  end,
}

---@class ContextCommand : CommandBase
local ContextCommand = {
  parse = function(args)
    return args[1]
  end,

  complete = function(arglead, args)
    return require("kubectl").context_names_sync()
  end,
}

M.command_handlers = {
  get = GetCommand,
  delete = GetCommand,
  context = ContextCommand,
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

    local parsed = handler.parse(args)
    M.commands[command](parsed)
  end, {
    nargs = "*",
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
      return handler.complete(arglead, args)
    end,
  })
end

M.commands = {
  get = function(resource_kind, params)
    require("kube").get(resource_kind, params)
  end,

  delete = function(resource_kind, params)
    require("kube").delete(resource_kind, params)
  end,

  context = function(context)
    require("kube").ctx(context)
  end,
}

return M
