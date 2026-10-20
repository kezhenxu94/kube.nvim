local log = require("kube.log")

---Actions receive the buffer the resource was selected from, which provides the context
---and, for subresource rows like containers, the parent resource.
---@class Actions
---@field drill_down_resource fun(kbuf: KubeBuffer, resource: table)|nil Drill down into the resource
---@field show_yaml fun(kbuf: KubeBuffer, resource: table)|nil Show the yaml buffer for the resource
---@field show_logs fun(kbuf: KubeBuffer, resource: table, follow: boolean)|nil Show the logs buffer for the resource
---@field port_forward fun(kbuf: KubeBuffer, resource: table)|nil Show the port forward buffer for the resource
---@field forward_port fun(kbuf: KubeBuffer, resource: table)|nil Forward the port for the resource
---@field describe fun(kbuf: KubeBuffer, resource: table)|nil Describe the resource
---@field set_image fun(kbuf: KubeBuffer, resource: table)|nil Set the image for the resource
---@field exec fun(kbuf: KubeBuffer, resource: table)|nil `exec` into the resource

local actions = {
  pod = require("kube.actions.pod"),
  container = require("kube.actions.container"),
  containers = require("kube.actions.container"),
  deployment = require("kube.actions.deployment"),
  cronjob = require("kube.actions.cronjob"),
  job = require("kube.actions.job"),
  daemonset = require("kube.actions.daemonset"),
  statefulset = require("kube.actions.statefulset"),
  replicaset = require("kube.actions.replicaset"),
  service = require("kube.actions.service"),
  secret = require("kube.actions.secret"),
  apiresource = require("kube.actions.apiresource"),
}

local non_object_rows = { container = true, containers = true, portforward = true, apiresource = true }

---@type table<string, Actions>
local M = {}

return setmetatable(M, {
  __index = function(_, key)
    local default_actions = require("kube.actions.default")
    local resource_actions = actions[key] or {}

    return setmetatable({}, {
      __index = function(_, action_name)
        log.debug("actions", key, action_name)

        local action = resource_actions[action_name]
        if action then
          return action
        end

        -- The defaults need a Kubernetes object, which container and port forward rows are not
        if not non_object_rows[key] then
          action = default_actions[action_name]
          if action then
            return action
          end
        end

        log.error("Unsupported action", action_name, "for", key)

        return nil
      end,
    })
  end,
})
