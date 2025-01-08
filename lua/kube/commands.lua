local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Kube", function(opts)
    local args = vim.split(opts.args, " ", { trimempty = true })
    local command = args[1]

    if M.commands[command] then
      M.commands[command](unpack(args, 2))
    else
      vim.notify("No such command: " .. (command or ""), vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, " ", { trimempty = true })

      if #args <= 2 then
        local commands = vim.tbl_keys(M.commands)
        if arglead and arglead ~= "" then
          return vim.tbl_filter(function(cmd)
            return vim.startswith(cmd, arglead)
          end, commands)
        end
        return commands
      end

      local command = args[2]
      local command_fn = M.commands[command]
      if not command_fn then return {} end

      local params = {}
      local info = debug.getinfo(command_fn, "u")
      for i = 1, info.nparams do
        local param_name = debug.getlocal(command_fn, i)
        table.insert(params, param_name)
      end

      if arglead and arglead ~= "" then
        return vim.tbl_filter(function(param)
          return vim.startswith(param, arglead)
        end, params)
      end
      return params
    end,
  })
end

M.commands = {
  get = function(resource_kind, namespace)
    require("kube").get(resource_kind, namespace)
  end,

  delete = function(resource_kind, resource_name, namespace)
    require("kube").delete(resource_kind, resource_name, namespace)
  end,
}

return M
