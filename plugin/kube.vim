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

command! -nargs=* -bang -complete=customlist,kube#commands#complete Kube call kube#commands#run(<q-args>, <bang>0)

augroup kube_autocmds
  autocmd!
  " Nested, so that the BufReadCmd of the buffer an alias redirects to runs
  autocmd BufReadCmd kube://* ++nested call kube#autocmds#read(str2nr(expand('<abuf>')))
  autocmd BufUnload kube://* call kube#autocmds#unload(str2nr(expand('<abuf>')))
  autocmd BufDelete,BufWipeout kube://* call kube#autocmds#delete(str2nr(expand('<abuf>')))
  autocmd BufWriteCmd kube://* call kube#autocmds#write(str2nr(expand('<abuf>')), v:cmdbang)
  autocmd TextChanged,TextChangedI kube://* call kube#autocmds#text_changed(str2nr(expand('<abuf>')))
  autocmd BufWinEnter kube://* call kube#autocmds#win_enter(str2nr(expand('<abuf>')))
  autocmd WinScrolled,WinResized * call kube#autocmds#scrolled()
  autocmd ColorScheme * call kube#highlights#setup()
  autocmd VimLeavePre * call kube#autocmds#leave()
augroup END

call kube#highlights#setup()
