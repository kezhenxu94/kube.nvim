local config = require("kube.config").values
local actions = require("kube.actions")
local constants = require("kube.constants")
local log = require("kube.log")

---@type Keymaps
local M = {
  setup_buffer_keymaps = function(buf_nr)
    local kbuf = _G.kube_buffers[buf_nr]
    local buf = kbuf.buf_nr
    local resource_kind = kbuf.resource_kind
    local namespace = kbuf.namespace
    local mark_mappings = kbuf.mark_mappings
    local subresource_kind = kbuf.subresource_kind
    log.debug("resource_kind", resource_kind, "namespace", namespace, "subresource_kind", subresource_kind)

    ---@type fun(): table<string, any>|nil
    local resource_under_cursor = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]

      local marks = vim.api.nvim_buf_get_extmarks(buf_nr, constants.KUBE_NAMESPACE, line, line, { details = true })
      log.debug("marks", marks)

      if #marks > 0 then
        local mark_id = marks[1][1]
        local resource = mark_mappings[mark_id].item
        log.debug("resource under cursor", resource)
        return resource
      end

      return nil
    end

    vim.keymap.set("n", config.keymaps.drill_down, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      if resource.kind then
        actions[resource.kind:lower()].drill_down_resource(resource)
      elseif subresource_kind then
        actions[subresource_kind:lower()].drill_down_resource(resource, {
          kind = kbuf.resource_kind,
          name = kbuf.resource_name,
          namespace = kbuf.namespace,
        })
      end
    end, {
      buffer = buf,
      desc = "kube: drill down to the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.show_logs, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      if resource.kind then
        actions[resource.kind:lower()].show_logs(resource, false, nil)
      elseif subresource_kind then
        actions[subresource_kind:lower()].show_logs(resource, false, {
          kind = kbuf.resource_kind,
          name = kbuf.resource_name,
          namespace = kbuf.namespace,
        })
      end
    end, {
      buffer = buf,
      desc = "kube: show logs for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.follow_logs, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      if resource.kind then
        actions[resource.kind:lower()].show_logs(resource, true, nil)
      elseif subresource_kind then
        actions[subresource_kind:lower()].show_logs(resource, true, {
          kind = kbuf.resource_kind,
          name = kbuf.resource_name,
          namespace = kbuf.namespace,
        })
      end
    end, {
      buffer = buf,
      desc = "kube: follow logs for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.port_forward, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      if resource.kind then
        actions[resource.kind:lower()].port_forward(resource, nil)
      elseif subresource_kind then
        actions[subresource_kind:lower()].port_forward(resource, {
          kind = kbuf.resource_kind,
          name = kbuf.resource_name,
          namespace = kbuf.namespace,
        })
      end
    end, {
      buffer = buf,
      desc = "kube: show port forwards for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.forward_port, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      if resource.kind then
        actions[resource.kind:lower()].forward_port(resource, nil)
      elseif subresource_kind then
        actions[subresource_kind:lower()].forward_port(resource, {
          kind = kbuf.resource_kind,
          name = kbuf.resource_name,
          namespace = kbuf.namespace,
        })
      end
    end, {
      buffer = buf,
      desc = "kube: forward ports for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.show_yaml, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      require("kube.actions.default").show_yaml(resource, nil)
    end, {
      buffer = buf,
      desc = "kube: show YAML for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.describe, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      actions[resource.kind:lower()].describe(resource, nil)
    end, {
      buffer = buf,
      desc = "kube: describe the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.edit, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      actions[resource.kind:lower()].edit(resource, nil)
    end, {
      buffer = buf,
      desc = "kube: edit the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.set_image, function()
      local resource = resource_under_cursor()
      if not resource then
        return
      end

      actions[resource.kind:lower()].set_image(kbuf, resource, nil)
    end, {
      buffer = buf,
      desc = "kube: set image for the resource under the cursor",
    })

    vim.keymap.set("n", config.keymaps.refresh, function()
      local parts = {}
      if namespace then
        table.insert(parts, namespace)
      end
      if resource_kind then
        table.insert(parts, resource_kind)
      end
      if kbuf.resource_name then
        table.insert(parts, kbuf.resource_name)
      end
      if kbuf.subresource_kind then
        table.insert(parts, kbuf.subresource_kind)
      end
      vim.notify(string.format("Refreshing %s", table.concat(parts, "/")))

      kbuf:load()
    end, {
      buffer = buf,
      desc = "kube: refresh the resources in the buffer",
    })
  end,
}

return M
