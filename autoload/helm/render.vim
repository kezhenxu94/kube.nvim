" Helm releases and their views:
" helm-releases[/{name}[/values|manifest|notes|history]].

" Views of a release that are text, by subresource, '' is helm status
let s:TEXT = {'': '', 'values': 'yaml', 'manifest': 'yaml', 'notes': ''}

function! helm#render#load(kbuf) abort
  let k = a:kbuf
  if empty(k.resource_name)
    return kube#buffer#track(k, helm#cli#list(k.context, k.namespace,
          \ function('s:render_json', [k, 'helm-releases']), kube#buffer#on_error(k)))
  endif
  if k.subresource_kind ==# 'history'
    return kube#buffer#track(k, helm#cli#history(k.context, k.resource_name, k.namespace,
          \ function('s:render_json', [k, 'helm-history']), kube#buffer#on_error(k)))
  endif

  if !has_key(s:TEXT, k.subresource_kind)
    call kube#ui#notify('Unsupported helm release view: ' . k.subresource_kind, 'error')
    return {}
  endif
  let Show = function('s:show', [k, s:TEXT[k.subresource_kind]])
  if empty(k.subresource_kind)
    return kube#buffer#track(k, helm#cli#status(k.context, k.resource_name, k.namespace, Show, kube#buffer#on_error(k)))
  endif
  let opts = {'all': get(k.params, 'all', v:false) is v:true}
  if has_key(k.params, 'revision')
    let opts.revision = k.params.revision
  endif
  return kube#buffer#track(k, helm#cli#get(k.context, k.subresource_kind, k.resource_name, k.namespace, opts, Show, kube#buffer#on_error(k)))
endfunction

function! s:render_json(kbuf, kind, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  " helm outputs null rather than [] when there is nothing
  let data = json_decode(a:result)
  call kube#table#render(a:kbuf, kube#format#get(a:kind), data is v:null ? [] : data, v:null)
endfunction

function! s:show(kbuf, filetype, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  if !empty(a:filetype)
    call setbufvar(a:kbuf.bufnr, '&filetype', a:filetype)
  endif
  call kube#buffer#set_lines(a:kbuf, split(trim(a:result), "\n", 1))
endfunction
