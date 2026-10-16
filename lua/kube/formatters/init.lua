---@class Formatter
---@field headers string[] List of column headers
---@field format fun(data: table, buffer: KubeBuffer): FormattedRow[] Function that takes raw data and returns formatted rows
---@field subresource_formatters table<string, Formatter[]>|nil Map of subresource name to formatter
---@field empty string|nil Status shown when there are no rows
---@class FormattedRow
---@field row table The row data containing column values
---@field item table The original resource item data
---@field diagnostics vim.Diagnostic[]|nil List of diagnostics for the row

local formatters = {
  {
    { "pods", "pod", "po" },
    require("kube.formatters.pods"),
  },
  {
    { "deployments", "deployment", "deploy", "deployments.apps", "deployment.apps" },
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
    { "ingresses", "ingress", "ing", "ingresses.networking.k8s.io", "ingress.networking.k8s.io" },
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
    { "events", "event", "ev" },
    require("kube.formatters.events"),
  },
  {
    { "portforwards" },
    require("kube.formatters.portforwards"),
  },
  {
    { "cronjobs", "cronjob", "cronjobs.batch", "cronjob.batch" },
    require("kube.formatters.cronjobs"),
  },
  {
    { "daemonsets", "daemonset", "ds", "daemonsets.apps", "daemonset.apps" },
    require("kube.formatters.daemonsets"),
  },
  {
    { "statefulsets", "statefulset", "sts", "statefulsets.apps", "statefulset.apps" },
    require("kube.formatters.statefulsets"),
  },
  {
    { "replicasets", "replicaset", "rs", "replicasets.apps", "replicaset.apps" },
    require("kube.formatters.replicasets"),
  },
  {
    { "gateways", "gateway", "gw", "gateways.networking.istio.io", "gateway.networking.istio.io" },
    require("kube.formatters.gateways"),
  },
}

-- Aliases include the group-qualified singular from `utils.resource_type`, used by parent buffers
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
