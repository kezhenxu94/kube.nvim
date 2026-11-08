" helm, run asynchronously. Callbacks get stdout on success, v:null on
" failure, error callbacks (optional: v:null) the stderr of failures.

" g:kube_request_timeout in milliseconds, helm has no --request-timeout.
" 0 for no timeout.
function! s:timeout_ms() abort
  let timeout = kube#config#get('request_timeout')
  if type(timeout) == v:t_number || timeout =~# '^\d\+$'
    return str2nr(timeout) * 1000
  endif
  let seconds = 0
  for [value, unit] in map(split(timeout, '\d\+[hms]\zs'), 'matchlist(v:val, ''\(\d\+\)\([hms]\)'')[1:2]')
    let seconds += str2nr(value) * {'h': 3600, 'm': 60, 's': 1}[unit]
  endfor
  return seconds * 1000
endfunction

function! s:namespace_args(namespace) abort
  return empty(a:namespace) || tolower(a:namespace) ==# 'all' ? [] : ['-n', a:namespace]
endfunction

" Run helm. A {mutation} is never killed: helm bounds its hooks with its own
" --timeout, and killing it mid-operation leaves the release stuck in a
" pending status.
function! s:helm(context, namespace, args, Callback, OnError, ...) abort
  let cmd = ['helm']
  if !empty(a:context)
    call extend(cmd, ['--kube-context', a:context])
  endif
  call extend(cmd, a:args + s:namespace_args(a:namespace))
  let opts = {'on_exit': function('s:on_exit', [a:Callback, a:OnError])}
  let timeout = s:timeout_ms()
  " Fail instead of hanging when the API server is unreachable
  if !get(a:, 1, 0) && timeout > 0
    let opts.timeout = timeout
  endif
  return kube#compat#run(cmd, opts)
endfunction

function! s:on_exit(Callback, OnError, code, stdout, stderr) abort
  let success = a:code == 0
  if !success && type(a:OnError) == v:t_func
    let err = trim(a:stderr)
    call a:OnError(a:code == 124 && empty(err) ? 'helm timed out' : err)
  endif
  if type(a:Callback) == v:t_func
    call a:Callback(success ? a:stdout : v:null)
  endif
endfunction

" Every status: helm 3 lists deployed and failed releases by default and
" helm 4 has no --all
let s:STATUSES = ['--deployed', '--failed', '--pending', '--superseded', '--uninstalled', '--uninstalling']

" The releases of all statuses as JSON, in {namespace}, 'all' for all.
function! helm#cli#list(context, namespace, Callback, OnError) abort
  let args = ['list'] + s:STATUSES + ['-o', 'json']
  if !empty(a:namespace) && tolower(a:namespace) ==# 'all'
    call add(args, '-A')
  endif
  return s:helm(a:context, a:namespace, args, a:Callback, a:OnError)
endfunction

function! helm#cli#status(context, name, namespace, Callback, OnError) abort
  return s:helm(a:context, a:namespace, ['status', a:name], a:Callback, a:OnError)
endfunction

" helm get {what} (values, manifest or notes) of the release {name}. {opts}:
" all, the computed values; revision.
function! helm#cli#get(context, what, name, namespace, opts, Callback, OnError) abort
  let args = ['get', a:what, a:name]
  if a:what ==# 'values'
    call extend(args, ['-o', 'yaml'])
    if get(a:opts, 'all', 0)
      call add(args, '--all')
    endif
  endif
  if get(a:opts, 'revision', v:null) isnot v:null
    call add(args, '--revision=' . kube#utils#to_string(a:opts.revision))
  endif
  return s:helm(a:context, a:namespace, args, a:Callback, a:OnError)
endfunction

" The revisions of the release {name} as JSON.
function! helm#cli#history(context, name, namespace, Callback, OnError) abort
  return s:helm(a:context, a:namespace, ['history', a:name, '-o', 'json'], a:Callback, a:OnError)
endfunction

" Roll back to {revision}, the previous one when v:null.
function! helm#cli#rollback(context, name, namespace, revision, Callback, OnError) abort
  let args = ['rollback', a:name]
  if a:revision isnot v:null
    call add(args, kube#utils#to_string(a:revision))
  endif
  return s:helm(a:context, a:namespace, args, a:Callback, a:OnError, 1)
endfunction

function! helm#cli#uninstall(context, name, namespace, Callback, OnError) abort
  return s:helm(a:context, a:namespace, ['uninstall', a:name], a:Callback, a:OnError, 1)
endfunction
