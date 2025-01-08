---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table): FormattedRow[] Function that takes raw data and returns formatted rows
---@field subresource_formatters table<string, Formatter[]>|nil Map of subresource name to formatter
---@class FormattedRow
---@field row table The row data containing column values
---@field item table The original resource item data

local formatters = {
  {
    { "pods", "pod", "po" },
    require("kube.formatters.pods"),
  },
  {
    { "deployments", "deployment", "deploy" },
    require("kube.formatters.deployments"),
  },
  {
    { "nodes", "node", "no" },
    require("kube.formatters.nodes"),
  },
  {
    { "namespaces", "namespace", "ns" },
    require("kube.formatters.namespaces"),
  },
  {
    { "services", "service", "svc" },
    require("kube.formatters.services"),
  },
  {
    { "ingresses", "ingress", "ing" },
    require("kube.formatters.ingresses"),
  },
  {
    { "configmaps", "configmap", "cm" },
    require("kube.formatters.configmaps"),
  },
  {
    { "secrets", "secret" },
    require("kube.formatters.secrets"),
  },
  {
    { "containers" },
    require("kube.formatters.containers"),
  },
  {
    { "portforward" },
    require("kube.formatters.portforward"),
  },
}

---@type table<string, Formatter>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    for _, formatter in ipairs(formatters) do
      for _, resource in ipairs(formatter[1]) do
        if resource == key then
          return formatter[2]
        end
      end
    end
    return require("kube.formatters.default")
  end,
})
