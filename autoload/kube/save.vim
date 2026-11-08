" What :w does, by kind of buffer, see the write() and delete() of resource.vim
" providers. Lists are resource.vim's: deleted rows delete their resources,
" cells of editable columns are applied, see kube#edits. The handlers of the
" other buffers are called with (kbuf, Callback, opts): Callback(saved) tells
" whether the buffer should be reloaded, opts.force (:w!) skips the
" confirmations.

function! kube#save#write(kbuf, force) abort
  if get(a:kbuf.params, 'output', '') is# 'yaml'
    let Save = function('s:save_yaml')
  elseif a:kbuf.subresource_kind ==# 'data'
    let Save = function('s:save_secret')
  elseif a:kbuf.subresource_kind ==# 'portforward' || a:kbuf.resource_kind ==# 'portforwards'
    let Save = function('s:save_portforwards')
  else
    return 0
  endif
  call Save(a:kbuf, {saved -> saved ? timer_start(0, {-> resource#load(a:kbuf)}) : 0}, {'force': a:force})
  return 1
endfunction

" The change deleting the item of a deleted row of a list: rows that are not
" resources, like the containers of a pod, cannot be deleted, Helm releases
" are uninstalled.
function! kube#save#delete(kbuf, item) abort
  if get(a:item, 'kind', '') ==# 'HelmRelease'
    return {
          \ 'title': printf('Uninstall helm release %s/%s', a:item.namespace, a:item.name),
          \ 'run': function('helm#cli#uninstall', [a:kbuf.context, a:item.name, a:item.namespace, v:null, v:null]),
          \ }
  elseif has_key(a:item, 'metadata')
    return {
          \ 'title': printf('Delete %s: %s/%s', kube#utils#resource_type(a:item), a:item.metadata.namespace, a:item.metadata.name),
          \ 'run': function('kube#kubectl#delete', [a:kbuf.context, kube#utils#resource_type(a:item), a:item.metadata.name,
          \   kube#utils#get(a:item.metadata, 'namespace', ''), v:null, v:null]),
          \ }
  endif
  return v:null
endfunction

" ---------------------------------------------------------------------------
" YAML: apply it after showing the diff

function! s:save_yaml(kbuf, Callback, opts) abort
  if !getbufvar(a:kbuf.bufnr, '&modified')
    call a:Callback(0)
    return
  endif
  call kube#apply#with_temp_file(getbufline(a:kbuf.bufnr, 1, '$'), function('s:apply_yaml', [a:kbuf, a:Callback, a:opts]))
endfunction

function! s:apply_yaml(kbuf, Callback, opts, file, Cleanup) abort
  let k = a:kbuf
  let title = printf('Apply %s/%s (context: %s)?', k.resource_kind, k.resource_name, k.context)
  call kube#apply#apply(k.context, k.namespace, a:file, {'force': a:opts.force, 'title': title},
        \ function('s:yaml_applied', [a:Callback, a:Cleanup]))
endfunction

function! s:yaml_applied(Callback, Cleanup, applied) abort
  call a:Cleanup()
  call a:Callback(a:applied)
endfunction

" ---------------------------------------------------------------------------
" Decoded secrets: patch the secret

function! s:save_secret(kbuf, Callback, opts) abort
  let k = a:kbuf
  let [new, err] = kube#secret#from_lines(getbufline(k.bufnr, 1, '$'))
  if new is v:null
    call resource#notify('Invalid secret data, ' . err, 'error')
    call a:Callback(0)
    return
  endif

  let old = kube#utils#get(k.data, 'data', {})
  let [patch, changes] = kube#secret#patch(old, new)
  if patch is v:null
    call resource#notify('No changes to apply')
    call a:Callback(1)
    return
  endif

  let Update = function('s:update_secret', [k, patch, a:Callback])
  if a:opts.force
    call Update(1)
    return
  endif
  let summary = []
  for change in ['added', 'changed', 'removed']
    if !empty(changes[change])
      call add(summary, change . ' ' . join(changes[change], ', '))
    endif
  endfor
  call resource#confirm(printf('Update secret %s/%s (context: %s): %s?', k.namespace, k.resource_name, k.context, join(summary, '; ')),
        \ {confirmed -> confirmed ? Update(1) : a:Callback(0)})
endfunction

function! s:update_secret(kbuf, patch, Callback, confirmed) abort
  call kube#kubectl#patch(a:kbuf.context, 'secret', a:kbuf.resource_name, a:kbuf.namespace, a:patch,
        \ function('s:secret_updated', [a:Callback]), {err -> resource#notify('Failed to update secret: ' . err, 'error')})
endfunction

function! s:secret_updated(Callback, result) abort
  if a:result isnot v:null
    call resource#notify(trim(a:result))
  endif
  call a:Callback(a:result isnot v:null)
endfunction

" ---------------------------------------------------------------------------
" Port forwards: stop those of deleted rows

function! s:save_portforwards(kbuf, Callback, opts) abort
  let forwards = resource#deleted(a:kbuf)
  if empty(forwards)
    call a:Callback(1)
    return
  endif

  if len(forwards) == 1
    let forward = forwards[0]
    let prompt = printf('Delete port forward: %s/%s?', forward.id, forward.local_port)
    call resource#confirm(prompt, function('s:stop_forwards', [forwards, a:Callback]))
    return
  endif
  let choices = ['cancel', 'all'] + forwards
  call resource#select(choices, {
        \ 'prompt': "Please select the port forwards to delete:\n",
        \ 'format_item': function('s:format_forward_choice'),
        \ }, function('s:on_forward_choice', [forwards, a:Callback]))
endfunction

function! s:format_forward_choice(item) abort
  if a:item is# 'cancel'
    return 'Cancel'
  elseif a:item is# 'all'
    return 'Delete all following port forwards'
  endif
  return printf('Delete port forward: %s/%s', a:item.id, a:item.local_port)
endfunction

function! s:on_forward_choice(forwards, Callback, choice, index) abort
  if a:choice is v:null
    return
  elseif a:choice is# 'all'
    call s:stop_forwards(a:forwards, a:Callback, 1)
  elseif a:choice is# 'cancel'
    call resource#notify('Deletion cancelled')
    call a:Callback(0)
  else
    call s:stop_forwards([a:choice], a:Callback, 1)
  endif
endfunction

function! s:stop_forwards(forwards, Callback, confirmed) abort
  if !a:confirmed
    call a:Callback(0)
    return
  endif
  for forward in a:forwards
    call kube#portforward#stop(forward.id, forward.local_port)
  endfor
  call a:Callback(1)
endfunction
