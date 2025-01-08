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

      if #args == 1 then
        return vim.tbl_keys(M.commands)
      end

      return {}
    end,
  })
end

M.commands = {
  get = function(resource_kind, namespace)
    require("kube").get(resource_kind, namespace)
  end,
}

return M
