local config = require("kube.config").values
local log = require("plenary.log").new({
  plugin = "kube.nvim",
  level = "debug",
})

return {
  debug = function(...)
    if config.log then
      log.debug(...)
    end
  end,
  info = function(...)
    if config.log then
      log.info(...)
    end
  end,
  error = function(...)
    if config.log then
      log.error(...)
    end
  end,
}
