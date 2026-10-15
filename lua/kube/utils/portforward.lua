local log = require("kube.log")

local M = {}

---@param context string The kubectl context
---@param ports table[] List of port configurations
---@param kind string Resource kind
---@param name string Resource name
---@param namespace string Resource namespace
function M.prompt_port_forward(context, ports, kind, name, namespace)
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

        local key = require("kube.utils").portforward_key(context, namespace, kind, name)
        if _G.portforwards[key] and _G.portforwards[key][local_port] then
          vim.notify(string.format("Local port %d is already used", local_port), vim.log.levels.ERROR)
          return
        end

        log.debug("forwarding port", port.container, port.port, local_port)

        vim.notify(string.format("Forwarding port %d to %d", port.port, local_port), vim.log.levels.INFO)
        local job
        job = require("kubectl").forward_port(context, kind, name, namespace, port.port, local_port, function(_)
          local forwards = _G.portforwards[key]
          if forwards and forwards[local_port] and forwards[local_port].job == job then
            forwards[local_port] = nil
          end
        end, function(data)
          vim.notify(data, vim.log.levels.ERROR)
        end)

        if job then
          _G.portforwards[key] = _G.portforwards[key] or {}
          _G.portforwards[key][local_port] = {
            container_port = port.port,
            job = job,
            context = context,
            namespace = namespace,
            resource_type = kind,
            name = name,
          }
        end

        prompt_port_forward()
      end)
    end)
  end

  prompt_port_forward()
end

return M
