" Opt-in periodic reload of lists ("watch"), toggled per buffer.

let s:timer = -1

" Tables that reflect the cluster state, as opposed to describe, YAML or logs.
function! kube#refresh#is_table(kbuf) abort
  return empty(a:kbuf.resource_name)
        \ || a:kbuf.subresource_kind ==# 'containers'
        \ || a:kbuf.subresource_kind ==# 'portforward'
        \ || (a:kbuf.resource_kind ==# 'helm-releases' && a:kbuf.subresource_kind ==# 'history')
endfunction

" The interval in milliseconds, 0 when watching is disabled.
function! kube#refresh#interval() abort
  let interval = kube#config#get('refresh_interval')
  return type(interval) == v:t_number ? interval : 0
endfunction

" What the header shows of a watched list.
function! kube#refresh#indicator() abort
  return printf('⟳ %gs', kube#refresh#interval() / 1000.0)
endfunction

function! s:should_refresh(kbuf) abort
  let buf = a:kbuf.bufnr
  if !a:kbuf.watch || !bufloaded(buf) || getbufvar(buf, '&modified') || kube#compat#running(a:kbuf.loading_job)
    return 0
  endif
  if empty(win_findbuf(buf))
    return 0
  endif
  " Do not move lines under a visual selection or a pending operator
  return bufnr('') != buf || mode() ==# 'n'
endfunction

function! s:tick(timer) abort
  let s:timer = -1
  let watching = 0
  for kbuf in kube#buffer#all()
    let watching = watching || kbuf.watch
    if s:should_refresh(kbuf)
      call kube#buffer#load(kbuf, {'silent': 1})
    endif
  endfor
  if watching
    call s:start()
  endif
endfunction

" Started again after each tick, with the interval of that time.
function! s:start() abort
  let interval = kube#refresh#interval()
  if s:timer == -1 && interval > 0
    let s:timer = timer_start(interval, function('s:tick'))
  endif
endfunction

" Toggle watching the buffer.
function! kube#refresh#toggle(kbuf) abort
  if !kube#refresh#is_table(a:kbuf)
    call kube#ui#notify('Only resource lists can be watched', 'warn')
    return
  endif
  if kube#refresh#interval() <= 0
    call kube#ui#notify('Watching is disabled, set g:kube_refresh_interval to enable it', 'warn')
    return
  endif
  let a:kbuf.watch = !a:kbuf.watch
  if a:kbuf.watch
    call s:start()
  endif
  call kube#utils#update_winbar(a:kbuf)
endfunction
