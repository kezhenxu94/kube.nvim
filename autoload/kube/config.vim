" The configuration: g:kube_{name} variables, read when used.

" Follows the conventions of Vim and Neovim: gd, K, <C-]> ('tagfunc') and the
" built-in directory browser (<CR>, -, R)
let s:keymaps = {
      \ 'drill_down': '<CR>',
      \ 'show_yaml': 'gd',
      \ 'owner': 'gD',
      \ 'describe': 'K',
      \ 'parent': '-',
      \ 'refresh': 'R',
      \ 'watch': 'gw',
      \ 'show_logs': 'gl',
      \ 'follow_logs': 'gL',
      \ 'port_forward': 'gF',
      \ 'forward_port': 'gf',
      \ 'set_image': 'gi',
      \ 'exec': 'gs',
      \ 'operations': 'gra',
      \ 'help': 'g?',
      \ }

let s:defaults = {
      \ 'refresh_interval': 10000,
      \ 'request_timeout': '30s',
      \ 'logs_tail': 1000,
      \ 'logs_max_lines': 10000,
      \ }

function! kube#config#get(name) abort
  if a:name ==# 'keymaps'
    return extend(copy(s:keymaps), get(g:, 'kube_keymaps', {}))
  endif
  return get(g:, 'kube_' . a:name, s:defaults[a:name])
endfunction
