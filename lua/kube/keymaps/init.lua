---@class Keymaps
---@field setup_buffer_keymaps fun(buf_nr: number) Setup the keymaps for the buffer

local keymaps = {
  default = require("kube.keymaps.default"),
}

---@type Keymaps
local M = {
  setup_buffer_keymaps = function(buf_nr)
    keymaps.default.setup_buffer_keymaps(buf_nr)
  end,
}

return M
