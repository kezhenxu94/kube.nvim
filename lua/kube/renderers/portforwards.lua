local formatters = require("kube.formatters")

---All port forwards, from the registry instead of kubectl.
---@type Renderer
local M = {
  load = function(buffer)
    require("kube.renderers.resources").render(buffer, formatters.portforwards, nil)
    return nil
  end,
}

return M
