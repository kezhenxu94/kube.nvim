---Cells of resource lists that can be edited and applied with `:w`, see `Formatter.editable`.
local kubectl = require("kubectl")
local utils = require("kube.utils")

local M = {}

---@class KubeEdit
---@field title string What the edit does, shown when confirming
---@field run fun(callback: fun(data: string|nil), on_error: fun(err: string))

---@alias KubeCellEditor fun(kbuf: KubeBuffer, item: table, old: string, new: string): KubeEdit|nil, string|nil

---@param input string|nil
---@return integer|nil
function M.parse_replicas(input)
  local replicas = tonumber(input)
  if not replicas or replicas < 0 or replicas % 1 ~= 0 then
    return nil
  end
  return replicas
end

---@param item table
---@return string
local function target(item)
  return string.format("%s/%s", utils.resource_type(item), item.metadata.name)
end

---Scale the resource of the row.
---@type KubeCellEditor
function M.replicas(kbuf, item, old, new)
  local replicas = M.parse_replicas(new)
  if not replicas then
    return nil, string.format("Invalid number of replicas for %s: %s", target(item), new)
  end
  return {
    title = string.format("Scale %s: %s → %d", target(item), old, replicas),
    run = function(callback, on_error)
      kubectl.scale(
        kbuf.context,
        utils.resource_type(item),
        item.metadata.name,
        item.metadata.namespace,
        replicas,
        callback,
        on_error
      )
    end,
  }
end

---Set the image of a container of the buffer's pod.
---@type KubeCellEditor
function M.image(kbuf, item, old, new)
  if new == "" or new:find("%s") then
    return nil, string.format("Invalid image for container %s: %q", item.name, new)
  end
  return {
    title = string.format(
      "Set image of %s/%s container %s: %s → %s",
      kbuf.resource_kind,
      kbuf.resource_name,
      item.name,
      old,
      new
    ),
    run = function(callback, on_error)
      kubectl.set_image(
        kbuf.context,
        kbuf.resource_kind,
        kbuf.resource_name,
        kbuf.namespace,
        item.name,
        new,
        callback,
        on_error
      )
    end,
  }
end

---Suspend or resume the cron job of the row.
---@type KubeCellEditor
function M.suspend(kbuf, item, old, new)
  if new ~= "true" and new ~= "false" then
    return nil, string.format("Invalid suspended value for %s, expected true or false: %s", target(item), new)
  end
  return {
    title = string.format("Set suspended of %s: %s → %s", target(item), old, new),
    run = function(callback, on_error)
      kubectl.patch(
        kbuf.context,
        utils.resource_type(item),
        item.metadata.name,
        item.metadata.namespace,
        { spec = { suspend = new == "true" } },
        callback,
        on_error
      )
    end,
  }
end

return M
