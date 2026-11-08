" Shells in containers: kube://.../{kind}/{name}/exec (param: container) and
" kube://.../pod/{name}/debug (params: image, target), started by BufReadCmd
" from their name, like term:// buffers.

function! kube#exec#start(name, parts) abort
  let params = a:parts.params
  if empty(a:parts.resource_name)
    call kube#ui#notify('Expected: kube://context/{context}/[namespaces/{ns}/]{kind}/{name}/' . a:parts.subresource_kind, 'error')
    return
  elseif a:parts.subresource_kind ==# 'exec'
    let cmd = kube#kubectl#exec_cmd(a:parts.context, a:parts.resource_kind, a:parts.resource_name, a:parts.namespace,
          \ get(params, 'container', ''))
  elseif type(get(params, 'image', v:null)) == v:t_string
    let cmd = kube#kubectl#debug_cmd(a:parts.context, a:parts.resource_name, a:parts.namespace, params.image,
          \ get(params, 'target', ''))
  else
    call kube#ui#notify('Expected the image of the debug container: ?image={image}', 'error')
    return
  endif
  call kube#compat#term_start(cmd, a:name)
endfunction

" Edit the shell buffer, started by BufReadCmd unless it already exists.
function! s:open_terminal(opts) abort
  call kube#utils#open(a:opts)
  call kube#compat#term_enter()
endfunction

" Call {OnChoice}(container) with the selected container, the only one
" without prompting, {} when there is none.
function! s:select_container(containers, prompt, OnChoice) abort
  if len(a:containers) <= 1
    call a:OnChoice(get(a:containers, 0, {}))
    return
  endif
  call kube#ui#select(a:containers, {'prompt': a:prompt, 'format_item': {item -> item.name}},
        \ {choice, index -> choice is v:null ? 0 : a:OnChoice(choice)})
endfunction

function! kube#exec#prompt_exec(context, containers, kind, name, namespace) abort
  call s:select_container(a:containers, 'Select container to exec into:',
        \ function('s:exec', [a:context, a:kind, a:name, empty(a:namespace) ? 'default' : a:namespace]))
endfunction

function! s:exec(context, kind, name, namespace, container) abort
  let opts = {'context': a:context, 'namespace': a:namespace, 'kind': a:kind, 'name': a:name, 'subresource': 'exec'}
  if !empty(a:container)
    let opts.params = {'container': a:container.name}
  endif
  call s:open_terminal(opts)
endfunction

" Open a shell in an ephemeral debug container of {pod}, sharing the process
" namespace of a container.
function! kube#exec#prompt_debug(context, pod) abort
  call kube#ui#input({'prompt': 'Debug image: ', 'default': 'busybox'}, function('s:on_image', [a:context, a:pod]))
endfunction

function! s:on_image(context, pod, image) abort
  if a:image is v:null
    return
  endif
  call s:select_container(a:pod.spec.containers, 'Select the container to debug:', function('s:debug', [a:context, a:pod, a:image]))
endfunction

function! s:debug(context, pod, image, container) abort
  let params = {'image': a:image}
  if !empty(a:container)
    let params.target = a:container.name
  endif
  call s:open_terminal({'context': a:context, 'namespace': a:pod.metadata.namespace, 'kind': 'pod',
        \ 'name': a:pod.metadata.name, 'subresource': 'debug', 'params': params})
endfunction
