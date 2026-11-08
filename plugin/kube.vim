" kube.nvim: manage Kubernetes resources like buffers
if exists('g:loaded_kube')
  finish
endif
let g:loaded_kube = 1

if has('nvim') ? !has('nvim-0.11') : !has('patch-9.2.0')
  echohl ErrorMsg
  echomsg 'kube.nvim requires Vim >= 9.2 or Neovim >= 0.11'
  echohl None
  finish
endif

if empty(globpath(&runtimepath, 'autoload/resource.vim'))
  echohl ErrorMsg
  echomsg 'kube.nvim requires resource.vim: https://github.com/kezhenxu94/resource.vim'
  echohl None
  finish
endif

command! -nargs=* -bang -complete=customlist,kube#commands#complete Kube call kube#commands#run(<q-args>, <bang>0)

augroup kube_autocmds
  autocmd!
  autocmd VimLeavePre * if exists('*kube#portforward#stop_all') | call kube#portforward#stop_all() | endif
augroup END

call resource#register(kube#provider#get())
