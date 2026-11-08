" What :w does, by kind of buffer. A handler is called with (kbuf, Callback,
" opts): Callback(saved) tells whether the buffer should be reloaded,
" opts.force (:w!) skips the confirmations.

function! kube#save#handler(kbuf) abort
  if get(a:kbuf.params, 'output', '') is# 'yaml'
    return function('s:save_yaml')
  elseif a:kbuf.subresource_kind ==# 'data'
    return function('s:save_secret')
  elseif a:kbuf.subresource_kind ==# 'portforward' || a:kbuf.resource_kind ==# 'portforwards'
    return function('s:save_portforwards')
  endif
  return function('s:save_list')
endfunction

" ---------------------------------------------------------------------------
" Lists: delete the resources of deleted rows, apply the edits of cells

function! s:describe_target(resource) abort
  return printf('%s: %s/%s', kube#utils#resource_type(a:resource), a:resource.metadata.namespace, a:resource.metadata.name)
endfunction

" The edits of the cells of editable columns: [edits, errors], the errors of
" the invalid ones and of the other edited cells.
function! s:cell_edits(kbuf, lines) abort
  let edits = []
  let errors = []
  let editable = get(kube#table#formatter_for(a:kbuf), 'editable', {})
  let cells = kube#compat#cells(a:kbuf.bufnr)
  " Marks are created in the order of the cells
  for id in sort(map(keys(a:kbuf.cells), 'str2nr(v:val)'), 'n')
    let cell = a:kbuf.cells[id]
    if cell.item is v:null || cell.row is v:null || get(a:lines, cell.row, 0) == 0 || !has_key(cells, id)
      continue
    endif
    let [lnum, start, end] = cells[id][0:2]
    let text = trim(strpart(getbufline(a:kbuf.bufnr, lnum)[0], start, end - start))
    if text ==# cell.text
      continue
    endif
    if !has_key(editable, cell.column)
      let item = has_key(cell.item, 'metadata') ? kube#utils#resource_type(cell.item) . '/' . cell.item.metadata.name : cell.item.name
      call add(errors, printf('%s of %s is not editable', cell.column, item))
      continue
    endif
    let [edit, err] = editable[cell.column](a:kbuf, cell.item, cell.text, text)
    if edit is v:null
      call add(errors, err)
    else
      call add(edits, edit)
    endif
  endfor
  return [edits, errors]
endfunction

function! s:save_list(kbuf, Callback, opts) abort
  let lines = kube#table#row_lines(a:kbuf)
  let [edits, errors] = s:cell_edits(a:kbuf, lines)
  if !empty(errors)
    call kube#ui#notify(join(errors, "\n"), 'error')
    call a:Callback(0)
    return
  endif

  let changes = copy(edits)
  " In the order of the rows
  for id in sort(map(keys(lines), 'str2nr(v:val)'), 'n')
    let item = a:kbuf.rows[id].item
    if lines[id] != 0
      continue
    endif
    " Rows that are not resources, like the containers of a pod, cannot be
    " deleted, Helm releases are uninstalled
    if get(item, 'kind', '') ==# 'HelmRelease'
      call add(changes, {
            \ 'title': printf('Uninstall helm release %s/%s', item.namespace, item.name),
            \ 'run': function('helm#cli#uninstall', [a:kbuf.context, item.name, item.namespace]),
            \ })
    elseif has_key(item, 'metadata')
      call add(changes, {
            \ 'title': 'Delete ' . s:describe_target(item),
            \ 'run': function('kube#kubectl#delete', [a:kbuf.context, kube#utils#resource_type(item), item.metadata.name,
            \   kube#utils#get(item.metadata, 'namespace', '')]),
            \ })
    endif
  endfor

  if empty(changes)
    call a:Callback(1)
    return
  endif
  if a:opts.force
    call s:run_changes(changes, a:Callback)
    return
  endif
  let titles = map(copy(changes), '"  " . v:val.title')
  let prompt = printf("Apply the changes (context: %s)?\n%s", a:kbuf.context, join(titles, "\n"))
  call kube#ui#confirm(prompt, function('s:on_confirm_changes', [changes, a:Callback]))
endfunction

function! s:on_confirm_changes(changes, Callback, confirmed) abort
  if a:confirmed
    call s:run_changes(a:changes, a:Callback)
  else
    call a:Callback(0)
  endif
endfunction

" Run the changes and reload once all are done, failed or not, to show what
" the cluster is now.
function! s:run_changes(changes, Callback) abort
  let state = {'remaining': len(a:changes), 'callback': a:Callback}
  for change in a:changes
    call change.run(function('s:change_done', [state]), function('s:change_failed', [state, change.title]))
  endfor
endfunction

function! s:change_done(state, result) abort
  if a:result isnot v:null
    call kube#ui#notify(trim(a:result))
  endif
  call s:change_finished(a:state)
endfunction

function! s:change_failed(state, title, err) abort
  call kube#ui#notify(printf("Failed: %s\n%s", a:title, a:err), 'error')
endfunction

function! s:change_finished(state) abort
  let a:state.remaining -= 1
  if a:state.remaining == 0
    call a:state.callback(1)
  endif
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
    call kube#ui#notify('Invalid secret data, ' . err, 'error')
    call a:Callback(0)
    return
  endif

  let old = kube#utils#get(k.data, 'data', {})
  let [patch, changes] = kube#secret#patch(old, new)
  if patch is v:null
    call kube#ui#notify('No changes to apply')
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
  call kube#ui#confirm(printf('Update secret %s/%s (context: %s): %s?', k.namespace, k.resource_name, k.context, join(summary, '; ')),
        \ {confirmed -> confirmed ? Update(1) : a:Callback(0)})
endfunction

function! s:update_secret(kbuf, patch, Callback, confirmed) abort
  call kube#kubectl#patch(a:kbuf.context, 'secret', a:kbuf.resource_name, a:kbuf.namespace, a:patch,
        \ function('s:secret_updated', [a:Callback]), {err -> kube#ui#notify('Failed to update secret: ' . err, 'error')})
endfunction

function! s:secret_updated(Callback, result) abort
  if a:result isnot v:null
    call kube#ui#notify(trim(a:result))
  endif
  call a:Callback(a:result isnot v:null)
endfunction

" ---------------------------------------------------------------------------
" Port forwards: stop those of deleted rows

function! s:save_portforwards(kbuf, Callback, opts) abort
  let lines = kube#table#row_lines(a:kbuf)
  let forwards = []
  for id in sort(map(keys(lines), 'str2nr(v:val)'), 'n')
    if lines[id] == 0
      call add(forwards, a:kbuf.rows[id].item)
    endif
  endfor
  if empty(forwards)
    call a:Callback(1)
    return
  endif

  if len(forwards) == 1
    let forward = forwards[0]
    let prompt = printf('Delete port forward: %s/%s?', forward.id, forward.local_port)
    call kube#ui#confirm(prompt, function('s:stop_forwards', [forwards, a:Callback]))
    return
  endif
  let choices = ['cancel', 'all'] + forwards
  call kube#ui#select(choices, {
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
    call kube#ui#notify('Deletion cancelled')
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
