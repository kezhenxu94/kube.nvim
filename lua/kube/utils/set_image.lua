local log = require("kube.log")

local M = {}

---@param containers table[] List of container configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
---@param callback fun(changed: boolean)
function M.prompt_set_image(containers, kind, name, namespace, callback)
  if #containers == 0 then
    vim.notify("No containers available", vim.log.levels.WARN)
    return
  end

  local container_strings = {}
  for i, container in ipairs(containers) do
    table.insert(container_strings, string.format("%s: %s", container.name, container.image))
  end

  vim.ui.select(container_strings, {
    prompt = "Select container to update:",
  }, function(choice, idx)
    if not choice or not idx then
      return
    end

    local container = containers[idx]
    if not container then
      return
    end

    vim.ui.input({
      prompt = "New image:",
      default = container.image,
    }, function(input)
      if not input then
        callback(false)
        return
      end

      log.debug("setting image for container", container.name, "to", input)

      require("kubectl").set_image(kind, name, namespace, container.name, input, function(success)
        if success then
          vim.notify(
            string.format("Successfully updated image for container '%s' to '%s'", container.name, input),
            vim.log.levels.INFO
          )
          callback(true)
        else
          callback(false)
        end
      end, function(err)
        if err then
          vim.schedule(function()
            vim.notify(err, vim.log.levels.ERROR)
          end)
          callback(false)
        end
      end)
    end)
  end)
end

return M
