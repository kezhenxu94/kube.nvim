local utils = require("kube.utils")

---@type Formatter
local M = {
  headers = { "NAMESPACE", "NAME", "HOSTS", "AGE" },

  format = function(data)
    local rows = {}

    for _, item in ipairs(data.items) do
      local hosts = {}
      for _, server in ipairs(item.spec.servers) do
        table.insert(hosts, server.hosts)
      end
      hosts = vim.tbl_flatten(hosts)
      hosts = vim.fn.uniq(vim.fn.sort(hosts))
      table.insert(rows, {
        row = {
          item.metadata.namespace,
          item.metadata.name,
          table.concat(hosts, ","),
          utils.calculate_age(item.metadata.creationTimestamp),
        },
        item = item,
      })
    end

    return rows
  end,
}

return M
