" The keymaps of kube buffers, see g:kube_keymaps.

let s:DESCRIPTIONS = {
      \ 'drill_down': 'drill down to the resource under the cursor',
      \ 'show_yaml': 'go to what the cell under the cursor refers to (YAML: :w applies it)',
      \ 'owner': 'go to the owner of the resource',
      \ 'describe': 'describe the resource under the cursor, explain a resource type',
      \ 'parent': 'go to the parent buffer',
      \ 'refresh': 'refresh the resources in the buffer',
      \ 'watch': 'toggle reloading the list periodically',
      \ 'show_logs': 'show logs for the resource under the cursor',
      \ 'follow_logs': 'follow logs for the resource under the cursor',
      \ 'port_forward': 'show port forwards for the resource under the cursor',
      \ 'forward_port': 'forward ports for the resource under the cursor',
      \ 'set_image': 'set image for the resource under the cursor',
      \ 'exec': 'exec into the resource under the cursor',
      \ 'operations': 'all operations on the resource, or on a visual selection',
      \ 'help': 'show this help',
      \ }

" [[lhs, description]] of the keymaps, sorted by lhs.
function! kube#keymaps#list() abort
  let keymaps = []
  for [name, lhs] in items(kube#config#get('keymaps'))
    if !empty(lhs) && has_key(s:DESCRIPTIONS, name)
      call add(keymaps, [lhs, s:DESCRIPTIONS[name]])
    endif
  endfor
  return sort(keymaps)
endfunction

function! kube#keymaps#setup(kbuf) abort
  if bufnr('') != a:kbuf.bufnr
    return
  endif
  for [name, lhs] in items(kube#config#get('keymaps'))
    if !empty(lhs)
      execute 'nnoremap <buffer> <silent> <nowait>' lhs ':<C-u>call kube#keymaps#run(' . string(name) . ')<CR>'
    endif
  endfor
  let operations = kube#config#get('keymaps').operations
  if !empty(operations)
    execute 'xnoremap <buffer> <silent> <nowait>' operations ':<C-u>call kube#keymaps#run("operations", line("''<"), line("''>"))<CR>'
  endif
  " Unhealthy resources, like diagnostics
  nnoremap <buffer> <silent> ]d :<C-u>call kube#keymaps#diagnostic(1)<CR>
  nnoremap <buffer> <silent> [d :<C-u>call kube#keymaps#diagnostic(-1)<CR>
  nnoremap <buffer> <silent> <C-w>d :<C-u>call kube#keymaps#show_diagnostics()<CR>
  call kube#compat#setup_tags(a:kbuf.bufnr)
endfunction

function! kube#keymaps#run(name, ...) abort
  let kbuf = kube#buffer#get(bufnr(''))
  if empty(kbuf)
    return
  endif
  if a:name ==# 'drill_down'
    call kube#actions#run(kbuf, 'drill_down_resource')
  elseif a:name ==# 'show_logs' || a:name ==# 'follow_logs'
    call kube#actions#run(kbuf, 'show_logs', a:name ==# 'follow_logs')
  elseif index(['port_forward', 'forward_port', 'set_image', 'exec'], a:name) >= 0
    call kube#actions#run(kbuf, a:name)
  elseif a:name ==# 'show_yaml'
    " What the cell refers to, mostly the YAML
    let target = kube#navigation#tag_target(kbuf, line('.'), col('.') - 1)
    if empty(target)
      call kube#actions#run(kbuf, 'show_yaml')
    else
      call kube#utils#edit(target)
    endif
  elseif a:name ==# 'owner'
    call s:owner(kbuf)
  elseif a:name ==# 'describe'
    call s:describe(kbuf)
  elseif a:name ==# 'parent'
    let parent = kube#navigation#parent_name(kbuf)
    if !empty(parent)
      call kube#utils#edit(parent)
    endif
  elseif a:name ==# 'refresh'
    call kube#buffer#load(kbuf)
  elseif a:name ==# 'watch'
    call kube#refresh#toggle(kbuf)
  elseif a:name ==# 'operations'
    call kube#operations#select(kbuf, get(a:, 1, line('.')), get(a:, 2, line('.')))
  elseif a:name ==# 'help'
    call kube#help#show()
  endif
endfunction

" Go to the next ({direction} 1) or previous (-1) line with diagnostics.
function! kube#keymaps#diagnostic(direction) abort
  let kbuf = kube#buffer#get(bufnr(''))
  let lines = kube#table#diagnostic_lines(kbuf)
  let candidates = a:direction > 0 ? filter(copy(lines), 'v:val > line(".")') : reverse(filter(copy(lines), 'v:val < line(".")'))
  if empty(candidates)
    call kube#ui#notify('No more unhealthy resources', 'warn')
    return
  endif
  call cursor(candidates[0], 1)
endfunction

" Show why the resource of the cursor line is unhealthy.
function! kube#keymaps#show_diagnostics() abort
  let diagnostics = kube#table#diagnostics(kube#buffer#get(bufnr('')), line('.'))
  if !empty(diagnostics)
    call kube#compat#float(map(copy(diagnostics), 'v:val.message'), {})
  endif
endfunction

" Describe the resource of the cursor line, explain a resource type, show the
" status of a Helm release.
function! s:describe(kbuf) abort
  let k = a:kbuf
  let item = kube#table#item_at(k, line('.'))
  if type(item) != v:t_dict
    return
  endif
  let kind = get(item, 'kind', '')
  let Show = function('s:show_float', [k.bufnr])
  let OnError = {err -> kube#ui#notify(err, 'error')}
  if kind ==# 'APIResource'
    call kube#kubectl#explain(k.context, item.name, Show, OnError)
  elseif kind ==# 'HelmRelease'
    call helm#cli#status(k.context, item.name, item.namespace, Show, OnError)
  elseif has_key(item, 'metadata') && !empty(kind)
    call kube#kubectl#describe(k.context, kube#utils#resource_type(item), item.metadata.name,
          \ kube#utils#get(item.metadata, 'namespace', ''), Show, OnError)
  endif
endfunction

function! s:show_float(bufnr, result) abort
  " Only while still in the buffer it was asked from
  if a:result isnot v:null && bufnr('') == a:bufnr
    call kube#compat#float(split(trim(a:result), "\n"), {})
  endif
endfunction

" Go to the owner of the resource of the cursor line, or of the buffer's
" resource: the controller first.
function! s:owner(kbuf) abort
  let k = a:kbuf
  if empty(k.resource_name) || !empty(k.subresource_kind)
    let item = kube#table#item_at(k, line('.'))
    call s:go_to_owner(k, type(item) == v:t_dict && has_key(item, 'metadata') ? item : v:null)
    return
  endif
  call kube#kubectl#get(k.context, k.resource_kind, k.resource_name, k.namespace, {},
        \ {result -> s:go_to_owner(k, result is v:null ? v:null : json_decode(result))}, v:null)
endfunction

function! s:go_to_owner(kbuf, resource) abort
  if a:resource is v:null
    return
  endif
  let owners = kube#utils#list(a:resource.metadata, 'ownerReferences')
  let controllers = filter(copy(owners), 'kube#utils#get(v:val, "controller", v:false) is v:true')
  let owner = get(controllers, 0, get(owners, 0, {}))
  if empty(owner)
    call kube#ui#notify('No owner', 'warn')
    return
  endif
  call kube#utils#open({'context': a:kbuf.context, 'namespace': kube#utils#get(a:resource.metadata, 'namespace', ''),
        \ 'kind': kube#utils#resource_type(owner), 'name': owner.name, 'params': {'output': 'yaml'}})
endfunction
