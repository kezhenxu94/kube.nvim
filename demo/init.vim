" Neovim of the demo: only kube.nvim, with the defaults
let &runtimepath = fnamemodify(expand('<sfile>:p'), ':h:h') . ',' . &runtimepath
set termguicolors shortmess+=I nohlsearch
set winborder=rounded
