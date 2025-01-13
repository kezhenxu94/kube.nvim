---@diagnostic disable: undefined-field
if _G.__is_log then
  return require("plenary.log").new({
    plugin = "kube.nvim",
    level = "debug",
  })
else
  return {
    debug = function(...) end,
    info = function(...) end,
    error = function(...) end,
  }
end
