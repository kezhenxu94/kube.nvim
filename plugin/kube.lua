if vim.g.loaded_kube then
  return
end
vim.g.loaded_kube = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("kube.nvim requires Neovim >= 0.11", vim.log.levels.ERROR)
  return
end

require("kube").init()
