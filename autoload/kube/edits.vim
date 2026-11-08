" Cells of lists that can be edited and applied with :w, see the editable
" columns of kube#format. An editor returns [edit, error]: the edit is a dict
" {title, run}, title is shown when confirming, run(Callback, OnError) applies
" it; v:null with an error when the value is invalid.

" The number of replicas {input}, -1 when invalid.
function! kube#edits#parse_replicas(input) abort
  return type(a:input) == v:t_string && a:input =~# '^\d\+$' ? str2nr(a:input) : -1
endfunction

function! s:target(item) abort
  return kube#utils#resource_type(a:item) . '/' . a:item.metadata.name
endfunction

" Scale the resource of the row.
function! kube#edits#replicas(kbuf, item, old, new) abort
  let replicas = kube#edits#parse_replicas(a:new)
  if replicas < 0
    return [v:null, printf('Invalid number of replicas for %s: %s', s:target(a:item), a:new)]
  endif
  return [{
        \ 'title': printf('Scale %s: %s → %d', s:target(a:item), a:old, replicas),
        \ 'run': function('kube#kubectl#scale', [a:kbuf.context, kube#utils#resource_type(a:item), a:item.metadata.name,
        \   a:item.metadata.namespace, replicas]),
        \ }, '']
endfunction

" Set the image of a container of the buffer's pod.
function! kube#edits#image(kbuf, item, old, new) abort
  if empty(a:new) || a:new =~# '\s'
    return [v:null, printf('Invalid image for container %s: %s', a:item.name, string(a:new))]
  endif
  return [{
        \ 'title': printf('Set image of %s/%s container %s: %s → %s', a:kbuf.resource_kind, a:kbuf.resource_name, a:item.name, a:old, a:new),
        \ 'run': function('kube#kubectl#set_image', [a:kbuf.context, a:kbuf.resource_kind, a:kbuf.resource_name,
        \   a:kbuf.namespace, a:item.name, a:new]),
        \ }, '']
endfunction

" Suspend or resume the cron job of the row.
function! kube#edits#suspend(kbuf, item, old, new) abort
  if a:new !=# 'true' && a:new !=# 'false'
    return [v:null, printf('Invalid suspended value for %s, expected true or false: %s', s:target(a:item), a:new)]
  endif
  return [{
        \ 'title': printf('Set suspended of %s: %s → %s', s:target(a:item), a:old, a:new),
        \ 'run': function('kube#kubectl#patch', [a:kbuf.context, kube#utils#resource_type(a:item), a:item.metadata.name,
        \   a:item.metadata.namespace, {'spec': {'suspend': a:new ==# 'true' ? v:true : v:false}}]),
        \ }, '']
endfunction
