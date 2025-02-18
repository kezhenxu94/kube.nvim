local log = require("kube.log")

local M = {}

---@param ports table[] List of port configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
function M.prompt_port_forward(ports, kind, name, namespace)
  if #ports == 0 then
    vim.notify("No ports available for port forwarding", vim.log.levels.WARN)
    return
  end

  local port_strings = {}
  for _, port in ipairs(ports) do
    table.insert(port_strings, string.format("%s: %d/%s", port.container, port.port, port.protocol))
  end

  local function prompt_port_forward()
    vim.ui.select(port_strings, {
      prompt = "Select container port to forward (q to finish):",
    }, function(choice, idx)
      if not choice or not idx then
        return
      end

      local port = ports[idx]
      if not port then
        return
      end

      vim.ui.input({
        prompt = string.format("Local port (default %d): ", port.port),
        default = tostring(port.port),
      }, function(input)
        if not input then
          return
        end

        local local_port = tonumber(input)
        if not local_port then
          vim.notify("Invalid port number", vim.log.levels.ERROR)
          return
        end

        local key = string.format("%s/%s", namespace, name)
        if _G.portforwards[key] and _G.portforwards[key][local_port] then
          vim.notify(string.format("Local port %d is already used", local_port), vim.log.levels.ERROR)
          return
        end

        log.debug("forwarding port", port.container, port.port, local_port)

        vim.notify(string.format("Forwarding port %d to %d", port.port, local_port), vim.log.levels.INFO)
        local job = require("kubectl").forward_port(kind, name, namespace, port.port, local_port, function(_)
          _G.portforwards[key] = _G.portforwards[key] or {}
          _G.portforwards[key][local_port] = nil
        end, function(data)
          if data then
            vim.schedule(function()
              vim.notify(data, vim.log.levels.ERROR)
            end)
          end
        end)

        if job then
          _G.portforwards[key] = _G.portforwards[key] or {}
          _G.portforwards[key][local_port] = {
            container_port = port.port,
            pid = job.pid,
          }
        end

        prompt_port_forward()
      end)
    end)
  end

  prompt_port_forward()
end

return M
