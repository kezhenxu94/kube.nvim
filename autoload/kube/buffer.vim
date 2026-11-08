" The state of kube buffers, by buffer number.
"
" A kube buffer (kbuf) is a dict:
"   bufnr, context, namespace ('all' for cluster-scoped / all namespaces),
"   resource_kind, resource_name, subresource_kind ('' when none), params,
"   data: the decoded kubectl output, header_row: the header of a table,
"   rows: {mark id: {item, line, signature}}, the rows of a table,
"   cells: {mark id: {item, column, text, row}}, the cells of a table,
"   diagnostics: {sign id: {message, severity}},
"   jobs: {job id: job}, loading_job: the job loading the buffer,
"   silent: whether the current load is a background refresh,
"   watch: whether the buffer reloads periodically, see kube#refresh,
"   loaded_callbacks: called once the current load is done.

let s:buffers = {}

function! kube#buffer#get(bufnr) abort
  return get(s:buffers, a:bufnr, {})
endfunction

function! kube#buffer#all() abort
  return values(s:buffers)
endfunction

function! kube#buffer#forget(bufnr) abort
  if has_key(s:buffers, a:bufnr)
    call remove(s:buffers, a:bufnr)
  endif
endfunction

" Parse a buffer name, see kube#utils#buf_name().
function! kube#buffer#parse_name(name) abort
  let [path, query] = matchlist(a:name, '^kube://\([^?]*\)?\=\(.*\)$')[1:2]
  let segments = split(path, '/')

  let context = ''
  if get(segments, 0, '') ==# 'context' && len(segments) >= 3
    let context = kube#utils#uri_decode(segments[1])
    let segments = segments[2:]
  endif
  let namespace = 'all'
  if get(segments, 0, '') ==# 'namespaces' && len(segments) >= 3
    let namespace = segments[1]
    let segments = segments[2:]
  endif
  let [kind, name, subresource] = (segments + ['', '', ''])[0:2]

  " The port forwards list spans all contexts
  if empty(kind) || (empty(context) && kind !=# 'portforwards')
    throw 'Invalid buffer name format. Expected: kube://context/{context}/[namespaces/{namespace}/]{resource_kind}'
  endif

  let params = {}
  for param in split(query, '&')
    let [key, value] = matchlist(param, '^\([^=]\+\)=\=\(.*\)$')[1:2]
    let params[key] = value ==# '' || value ==# 'true' ? v:true : value ==# 'false' ? v:false : value
  endfor

  return {
        \ 'context': context,
        \ 'namespace': namespace,
        \ 'resource_kind': kind,
        \ 'resource_name': name,
        \ 'subresource_kind': subresource,
        \ 'params': params,
        \ }
endfunction

" The kube buffer of {bufnr}, created from its name the first time.
function! kube#buffer#new(bufnr) abort
  if has_key(s:buffers, a:bufnr)
    return s:buffers[a:bufnr]
  endif
  let kbuf = extend({
        \ 'bufnr': a:bufnr,
        \ 'rows': {},
        \ 'cells': {},
        \ 'diagnostics': {},
        \ 'jobs': {},
        \ 'loading_job': {},
        \ 'loaded_callbacks': [],
        \ 'header_row': {},
        \ 'data': v:null,
        \ 'silent': 0,
        \ 'watch': 0,
        \ }, kube#buffer#parse_name(bufname(a:bufnr)))
  let s:buffers[a:bufnr] = kbuf
  call kube#buffer#setup(kbuf)
  call kube#keymaps#setup(kbuf)
  return kbuf
endfunction

function! kube#buffer#setup(kbuf) abort
  " Logs can be edited, e.g. reformatted, but there is nothing to write: :w
  " fails instead of reloading them, and the edits never block quitting.
  " :w {file} saves them.
  call setbufvar(a:kbuf.bufnr, '&buftype', a:kbuf.subresource_kind ==# 'logs' ? 'nofile' : 'acwrite')
  call setbufvar(a:kbuf.bufnr, '&swapfile', 0)
endfunction

" Load the buffer. {opts}: silent, for background refreshes: no loading
" status, no error notification.
function! kube#buffer#load(kbuf, ...) abort
  let opts = get(a:, 1, {})
  " Operations reload their buffer when done, it may have been unloaded or
  " deleted meanwhile
  if !bufloaded(a:kbuf.bufnr) || get(s:buffers, a:kbuf.bufnr, {}) isnot a:kbuf
    return
  endif
  if kube#compat#running(a:kbuf.loading_job)
    if !get(opts, 'silent', 0)
      call kube#ui#notify('The buffer is currently being loaded', 'warn')
    endif
    return
  endif

  let a:kbuf.silent = get(opts, 'silent', 0)
  if getbufline(a:kbuf.bufnr, 1, '$') == ['']
    call kube#buffer#set_status(a:kbuf, 'Loading…', 'Comment')
  endif
  let a:kbuf.loading_job = kube#render#load(a:kbuf)
endfunction

" Kill the jobs loading the buffer, their output has nowhere to go once it is
" unloaded.
function! kube#buffer#stop_jobs(kbuf) abort
  call kube#compat#kill(a:kbuf.loading_job)
  let a:kbuf.loading_job = {}
  for job in values(a:kbuf.jobs)
    call kube#compat#kill(job)
  endfor
  let a:kbuf.jobs = {}
endfunction

" Track a job of the buffer, so that it is stopped with the buffer.
function! kube#buffer#track(kbuf, job) abort
  if !empty(a:job)
    let a:kbuf.jobs[a:job.id] = a:job
  endif
  return a:job
endfunction

" Show a status after the first line, v:null to clear it.
function! kube#buffer#set_status(kbuf, text, hl) abort
  call kube#compat#set_status(a:kbuf.bufnr, 1, a:text, a:hl)
endfunction

" Call {Fn}(err) once the buffer is loaded, after it is rendered, or with the
" error of the load.
function! kube#buffer#on_loaded(kbuf, Fn) abort
  call add(a:kbuf.loaded_callbacks, a:Fn)
endfunction

function! kube#buffer#notify_loaded(kbuf, err) abort
  let callbacks = a:kbuf.loaded_callbacks
  let a:kbuf.loaded_callbacks = []
  " Renderers set the lines, then the marks
  call timer_start(0, function('s:run_callbacks', [callbacks, a:err]))
endfunction

function! s:run_callbacks(callbacks, err, timer) abort
  for Fn in a:callbacks
    call Fn(a:err)
  endfor
endfunction

" The error callback of kubectl calls loading the buffer.
function! kube#buffer#on_error(kbuf) abort
  return function('s:on_error', [a:kbuf])
endfunction

function! s:on_error(kbuf, err) abort
  call kube#buffer#notify_loaded(a:kbuf, a:err)
  let message = split(empty(a:err) ? 'kubectl failed' : a:err, "\n")[0]
  call kube#buffer#set_status(a:kbuf, '✗ ' . message, 'ErrorMsg')
  if !a:kbuf.silent
    call kube#ui#notify(a:err, 'error')
  endif
endfunction

" Replace the lines of the buffer, keeping it unmodified.
function! kube#buffer#set_lines(kbuf, lines, ...) abort
  let buf = a:kbuf.bufnr
  call kube#buffer#set_status(a:kbuf, v:null, '')
  call setbufvar(buf, '&modifiable', 1)
  silent call deletebufline(buf, 1, '$')
  call setbufline(buf, 1, a:lines)
  call setbufvar(buf, '&modifiable', get(a:, 1, 0) ? 1 : 0)
  call setbufvar(buf, '&modified', 0)
  call kube#buffer#notify_loaded(a:kbuf, v:null)
endfunction
