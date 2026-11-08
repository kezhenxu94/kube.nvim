" Port forwards, of all buffers and contexts: {key: {local port: forward}},
" see kube#utils#portforward_key(). A forward is a dict: container_port, job,
" context, namespace, resource_type, name.

let s:forwards = {}

function! kube#portforward#all() abort
  return s:forwards
endfunction

" Stop the forward of {local_port} of the resource {key}.
function! kube#portforward#stop(key, local_port) abort
  let forwards = get(s:forwards, a:key, {})
  if has_key(forwards, a:local_port)
    call kube#compat#kill(forwards[a:local_port].job)
    call remove(forwards, a:local_port)
  endif
endfunction

function! kube#portforward#stop_all() abort
  for forwards in values(s:forwards)
    for forward in values(forwards)
      call kube#compat#kill(forward.job)
    endfor
  endfor
  let s:forwards = {}
endfunction

" Prompt for the ports of {ports} ([{container, port, protocol}]) to forward,
" until none is selected.
function! kube#portforward#prompt(context, ports, kind, name, namespace) abort
  if empty(a:ports)
    call kube#ui#notify('No ports available for port forwarding', 'warn')
    return
  endif
  let choices = map(copy(a:ports), 'printf("%s: %d/%s", v:val.container, v:val.port, v:val.protocol)')
  call kube#ui#select(choices, {'prompt': 'Select container port to forward (q to finish):'},
        \ function('s:on_port', [a:context, a:ports, a:kind, a:name, a:namespace]))
endfunction

function! s:on_port(context, ports, kind, name, namespace, choice, index) abort
  if a:choice is v:null
    return
  endif
  let port = a:ports[a:index - 1]
  call kube#ui#input({'prompt': printf('Local port (default %d): ', port.port), 'default': string(port.port)},
        \ function('s:on_local_port', [a:context, a:ports, a:kind, a:name, a:namespace, port]))
endfunction

function! s:on_local_port(context, ports, kind, name, namespace, port, input) abort
  if a:input is v:null
    return
  endif
  if a:input !~# '^\d\+$'
    call kube#ui#notify('Invalid port number', 'error')
    return
  endif
  let local_port = str2nr(a:input)
  let key = kube#utils#portforward_key(a:context, a:namespace, a:kind, a:name)
  if has_key(get(s:forwards, key, {}), local_port)
    call kube#ui#notify(printf('Local port %d is already used', local_port), 'error')
    return
  endif

  call kube#ui#notify(printf('Forwarding port %d to %d', a:port.port, local_port))
  let forward = {
        \ 'container_port': a:port.port,
        \ 'context': a:context,
        \ 'namespace': a:namespace,
        \ 'resource_type': a:kind,
        \ 'name': a:name,
        \ }
  let forward.job = kube#kubectl#forward_port(a:context, a:kind, a:name, a:namespace, a:port.port, local_port,
        \ function('s:on_exit', [key, local_port, forward]), {err -> kube#ui#notify(err, 'error')})
  if !empty(forward.job)
    let s:forwards[key] = get(s:forwards, key, {})
    let s:forwards[key][local_port] = forward
  endif

  call kube#portforward#prompt(a:context, a:ports, a:kind, a:name, a:namespace)
endfunction

function! s:on_exit(key, local_port, forward, result) abort
  let forwards = get(s:forwards, a:key, {})
  if get(forwards, a:local_port, {}) is a:forward
    call remove(forwards, a:local_port)
  endif
endfunction
