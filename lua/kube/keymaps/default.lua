local actions = require("kube.actions")
local constants = require("kube.constants")
local log = require("kube.log")

---@param kbuf KubeBuffer
---@return table|nil The resource under the cursor
local function resource_under_cursor(kbuf)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local marks = vim.api.nvim_buf_get_extmarks(kbuf.buf_nr, constants.KUBE_NAMESPACE, { row, 0 }, { row, -1 }, {})
  local marked_line = marks[1] and kbuf.mark_mappings[marks[1][1]]
  log.debug("resource under cursor", marked_line)
  return marked_line and marked_line.item
end

---Run the action for the resource under the cursor. Rows without a `kind`
---(e.g. containers) are dispatched by the buffer's subresource kind.
---@param kbuf KubeBuffer
---@param action_name string
---@param ... any Extra arguments for the action
local function run_action(kbuf, action_name, ...)
  local resource = resource_under_cursor(kbuf)
  if not resource then
    return
  end

  local kind = resource.kind or kbuf.subresource_kind
  if not kind then
    return
  end

  local action = actions[kind:lower()][action_name]
  if not action then
    vim.notify(string.format("%s is not supported for %s", action_name, kind), vim.log.levels.WARN)
    return
  end
  action(kbuf, resource, ...)
end

---@type Keymaps
local M = {
  setup_buffer_keymaps = function(buf_nr)
    local config = require("kube.config").values
    local kbuf = _G.kube_buffers[buf_nr]

    ---@param lhs string
    ---@param desc string
    ---@param fn function
    local function map(lhs, desc, fn)
      vim.keymap.set("n", lhs, fn, { buffer = buf_nr, desc = "kube: " .. desc })
    end

    ---@param lhs string
    ---@param desc string
    ---@param action_name string
    ---@param ... any Extra arguments for the action
    local function map_action(lhs, desc, action_name, ...)
      local args = { ... }
      map(lhs, desc, function()
        run_action(kbuf, action_name, unpack(args))
      end)
    end

    map_action(config.keymaps.drill_down, "drill down to the resource under the cursor", "drill_down_resource")
    map_action(config.keymaps.show_logs, "show logs for the resource under the cursor", "show_logs", false)
    map_action(config.keymaps.follow_logs, "follow logs for the resource under the cursor", "show_logs", true)
    map_action(config.keymaps.port_forward, "show port forwards for the resource under the cursor", "port_forward")
    map_action(config.keymaps.forward_port, "forward ports for the resource under the cursor", "forward_port")
    -- Like the LSP definition: what the cell refers to (see kube.navigation), mostly the YAML
    map(config.keymaps.show_yaml, "go to what the cell under the cursor refers to (YAML: :w applies it)", function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local target = require("kube.navigation").tag_target(kbuf, { cursor[1] - 1, cursor[2] })
      if target then
        vim.cmd.edit(vim.fn.fnameescape(target))
      else
        run_action(kbuf, "show_yaml")
      end
    end)

    map_action(config.keymaps.set_image, "set image for the resource under the cursor", "set_image")
    map_action(config.keymaps.exec, "exec into the resource under the cursor", "exec")

    vim.bo[buf_nr].tagfunc = "v:lua.require'kube.navigation'.tagfunc"

    map(config.keymaps.parent, "go to the parent buffer", function()
      local parent = require("kube.navigation").parent_name(kbuf)
      if parent then
        vim.cmd.edit(vim.fn.fnameescape(parent))
      end
    end)

    map(config.keymaps.help, "show this help", function()
      require("kube.help").show(buf_nr)
    end)

    map(config.keymaps.describe, "describe the resource under the cursor (LSP hover)", function()
      vim.lsp.buf.hover()
    end)

    map(config.keymaps.watch, "toggle reloading the list periodically", function()
      require("kube.refresh").toggle(kbuf)
    end)

    map(config.keymaps.refresh, "refresh the resources in the buffer", function()
      kbuf:load()
    end)

    map(config.keymaps.quit, "quit the buffer", function()
      if not vim.api.nvim_get_option_value("modified", { buf = buf_nr }) then
        vim.api.nvim_buf_delete(buf_nr, { force = true })
        return
      end

      require("kube.events").for_buffer(kbuf).on_buf_saved(buf_nr, function(saved)
        if saved then
          vim.schedule(function()
            vim.api.nvim_buf_delete(buf_nr, { force = true })
          end)
        end
      end)
    end)
  end,
}

return M
