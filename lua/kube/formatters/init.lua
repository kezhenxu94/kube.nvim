---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table): FormattedRow[] Function that takes raw data and returns formatted rows
---@field subresource_formatters table<string, Formatter[]>|nil Map of subresource name to formatter
---@class FormattedRow
---@field row table The row data containing column values
---@field item table The original resource item data
---@field diagnostics vim.diagnostic[]|nil List of diagnostics for the row

local formatters = {
  {
    { "pods", "pod", "po" },
    require("kube.formatters.pods"),
  },
  {
    { "deployments", "deployment", "deploy", "deployments.apps" },
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
  {
    { "cronjobs", "cronjob", "cronjobs.batch" },
    require("kube.formatters.cronjobs"),
  },
  {
    { "daemonsets", "daemonset", "ds", "daemonsets.apps" },
    require("kube.formatters.daemonsets"),
  },
  {
    { "statefulsets", "statefulset", "sts", "statefulsets.apps" },
    require("kube.formatters.statefulsets"),
  },
  {
    { "replicasets", "replicaset", "rs", "replicasets.apps" },
    require("kube.formatters.replicasets"),
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
