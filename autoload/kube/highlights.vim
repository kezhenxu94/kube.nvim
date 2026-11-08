" Highlights link to the colorscheme's groups by default, so colorschemes and
" :highlight take precedence. g:kube_highlights overrides them, also after
" changing the colorscheme: {group: ':highlight arguments'}.
function! kube#highlights#setup() abort
  for [group, link] in items(kube#compat#highlight_links())
    execute 'highlight default link' group link
  endfor
  for [group, attributes] in items(get(g:, 'kube_highlights', {}))
    execute 'highlight' group attributes
  endfor
  for [severity, text] in [['Error', 'E'], ['Warn', 'W'], ['Info', 'I']]
    call sign_define('KubeSign' . severity, {'text': text, 'texthl': 'KubeSign' . severity})
  endfor
endfunction
