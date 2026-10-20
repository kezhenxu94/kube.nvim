-- Neovim of the demo: only kube.nvim, with the defaults
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.termguicolors = true
vim.opt.shortmess:append("I")
vim.o.winborder = "rounded"
vim.o.hlsearch = false
