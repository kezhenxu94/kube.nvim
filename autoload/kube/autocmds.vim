" The autocommands of kube:// buffers, see plugin/kube.vim.

" The name of the buffer {name} is an alias of, itself if none: without
" context/{context}/ it is pinned to the current context, so that the buffer
" keeps operating on the same cluster after the context is switched; ctx is
" short for context, ns for namespaces, helm for helm-releases; no kind is the
" resource types, api-resources.
" Returns [name, error].
function! kube#autocmds#canonical_name(name) abort
  if a:name ==# 'kube://portforwards'
    return [a:name, '']
  endif

  let rest = substitute(strpart(a:name, len('kube://')), '^/\+', '', '')
  let rest = substitute(rest, '^ctx/', 'context/', '')
  let context = matchstr(rest, '^context/[^/?]*/\=')
  if !empty(context)
    let rest = strpart(rest, len(context))
    if context !~# '/$'
      let context .= '/'
    endif
  else
    let current = kube#kubectl#get_current_context()
    if empty(current)
      return ['', 'No current kubectl context']
    endif
    let context = 'context/' . kube#utils#uri_encode(current) . '/'
  endif
  let rest = substitute(rest, '^ns$', 'namespaces', '')
  let rest = substitute(rest, '^ns\([/?]\)', 'namespaces\1', '')
  let namespace = matchstr(rest, '^namespaces/[^/?]\+/')
  let kind = strpart(rest, len(namespace))
  if kind ==# 'helm' || kind =~# '^helm[/?]'
    let rest = namespace . 'helm-releases' . strpart(kind, len('helm'))
  endif
  if empty(rest)
    let rest = 'api-resources'
  endif
  return ['kube://' . context . rest, '']
endfunction

function! kube#autocmds#read(bufnr) abort
  let name = bufname(a:bufnr)
  let [canonical, err] = kube#autocmds#canonical_name(name)
  if !empty(err)
    call kube#ui#notify(err, 'error')
    return
  endif
  " The name is an alias: edit the canonical buffer instead, the alias is
  " wiped, it never becomes the alternate file or a jump.
  if canonical !=# name
    let target = bufadd(canonical)
    call setbufvar(target, '&buflisted', 1)
    execute 'keepalt keepjumps buffer' target
    call timer_start(0, function('s:wipe', [a:bufnr]))
    return
  endif

  try
    let parts = kube#buffer#parse_name(name)
  catch /^Invalid buffer name/
    call kube#ui#notify(v:exception, 'error')
    return
  endtry
  if parts.subresource_kind ==# 'exec' || parts.subresource_kind ==# 'debug'
    call kube#exec#start(name, parts)
    return
  endif
  call kube#buffer#load(kube#buffer#new(a:bufnr))
endfunction

function! s:wipe(bufnr, timer) abort
  if bufexists(a:bufnr)
    silent! execute 'bwipeout!' a:bufnr
  endif
endfunction

" An unloaded buffer (:bunload, leaving it with 'nohidden', :e) keeps its
" state, e.g. watching, for when it is loaded again, a deleted one (:bdelete,
" :bwipeout) starts over.
function! kube#autocmds#unload(bufnr) abort
  let kbuf = kube#buffer#get(a:bufnr)
  if !empty(kbuf)
    call kube#buffer#stop_jobs(kbuf)
  endif
endfunction

function! kube#autocmds#delete(bufnr) abort
  let kbuf = kube#buffer#get(a:bufnr)
  if !empty(kbuf)
    call kube#buffer#stop_jobs(kbuf)
    call kube#buffer#forget(a:bufnr)
  endif
endfunction

function! kube#autocmds#write(bufnr, bang) abort
  let kbuf = kube#buffer#get(a:bufnr)
  if empty(kbuf)
    return
  endif
  let Save = kube#save#handler(kbuf)
  call Save(kbuf, function('s:saved', [kbuf]), {'force': a:bang})
endfunction

function! s:saved(kbuf, saved) abort
  if a:saved
    call timer_start(0, {-> kube#buffer#load(a:kbuf)})
  endif
endfunction

function! kube#autocmds#text_changed(bufnr) abort
  let kbuf = kube#buffer#get(a:bufnr)
  if !empty(kbuf) && !empty(kbuf.rows)
    call kube#table#show_pending(kbuf)
  endif
endfunction

function! kube#autocmds#win_enter(bufnr) abort
  let kbuf = kube#buffer#get(a:bufnr)
  " Wrapped rows break the table layout and its alignment with the header
  if !empty(kbuf) && kube#refresh#is_table(kbuf)
    setlocal nowrap
  endif
endfunction

function! kube#autocmds#scrolled() abort
  if bufname('') !~# '^kube://'
    return
  endif
  let kbuf = kube#buffer#get(bufnr(''))
  if !empty(kbuf)
    call kube#utils#update_winbar(kbuf)
  endif
endfunction

" Stop all kubectl jobs when exiting.
function! kube#autocmds#leave() abort
  for kbuf in kube#buffer#all()
    call kube#buffer#stop_jobs(kbuf)
  endfor
  call kube#portforward#stop_all()
endfunction
