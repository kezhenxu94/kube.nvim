---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table): FormattedRow[] Function that takes raw data and returns formatted rows
---@field subresource_formatters table<string, Formatter[]>|nil Map of subresource name to formatter
---@class FormattedRow
---@field row table The row data containing column values
---@field item table The original resource item data

local formatters = {
  pods = require("kube.formatters.pods"),
  deployments = require("kube.formatters.deployments"),
  nodes = require("kube.formatters.nodes"),
  namespaces = require("kube.formatters.namespaces"),
  services = require("kube.formatters.services"),
  ingresses = require("kube.formatters.ingresses"),
  configmaps = require("kube.formatters.configmaps"),
  secrets = require("kube.formatters.secrets"),
  containers = require("kube.formatters.containers"),
  portforward = require("kube.formatters.portforward"),
}

---@type table<string, Formatter>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    return formatters[key] or require("kube.formatters.default")
  end,
})
