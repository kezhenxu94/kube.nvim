" The kube provider of resource.vim: the buffers
" kube://[context/{context}/][namespaces/{ns}/]{kind}[/{name}[/{subresource}]][?{params}],
" see kube#utils#buf_name().

function! kube#provider#get() abort
  return {
        \ 'name': 'kube',
        \ 'title': 'kube.nvim',
        \ 'parse': function('kube#provider#parse'),
        \ 'canonical': function('kube#provider#canonical'),
        \ 'load': function('kube#render#load'),
        \ 'term': function('kube#exec#term'),
        \ 'identity': function('kube#provider#identity'),
        \ 'label': function('kube#provider#label'),
        \ 'scope': {kbuf -> 'context: ' . kbuf.context},
        \ 'parent': function('kube#navigation#parent_name'),
        \ 'tag': function('kube#navigation#tag_target'),
        \ 'delete': function('kube#save#delete'),
        \ 'write': function('kube#save#write'),
        \ 'operations': function('kube#operations#for_items'),
        \ 'keymaps': s:KEYMAPS,
        \ 'help': s:HELP,
        \ 'highlights': {
        \   'KubePending': ['DiagnosticWarn', 'WarningMsg'],
        \   'KubeRunning': 'Normal',
        \   'KubeFailed': ['DiagnosticError', 'ErrorMsg'],
        \   'KubeSucceeded': 'Comment',
        \   'KubeUnknown': 'Comment',
        \ },
        \ 'defaults': {'request_timeout': '30s', 'logs_tail': 1000},
        \ 'volatile': ['AGE', 'LAST SEEN', 'CPU', 'MEMORY'],
        \ }
endfunction

" Follows the conventions of Vim and Neovim: gd, K, <C-]> ('tagfunc') and the
" built-in directory browser (<CR>, -, R). parent, refresh, watch, operations
" and help are resource.vim's.
let s:KEYMAPS = {
      \ 'drill_down': {'lhs': '<CR>', 'desc': 'drill down to the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'drill_down_resource')}},
      \ 'show_yaml': {'lhs': 'gd', 'desc': 'go to what the cell under the cursor refers to (YAML: :w applies it)',
      \   'run': {kbuf -> s:show_yaml(kbuf)}},
      \ 'owner': {'lhs': 'gD', 'desc': 'go to the owner of the resource', 'run': {kbuf -> s:owner(kbuf)}},
      \ 'describe': {'lhs': 'K', 'desc': 'describe the resource under the cursor, explain a resource type',
      \   'run': {kbuf -> s:describe(kbuf)}},
      \ 'refresh': {'desc': 'refresh the resources in the buffer'},
      \ 'show_logs': {'lhs': 'gl', 'desc': 'show logs for the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'show_logs', 0)}},
      \ 'follow_logs': {'lhs': 'gL', 'desc': 'follow logs for the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'show_logs', 1)}},
      \ 'port_forward': {'lhs': 'gF', 'desc': 'show port forwards for the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'port_forward')}},
      \ 'forward_port': {'lhs': 'gf', 'desc': 'forward ports for the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'forward_port')}},
      \ 'set_image': {'lhs': 'gi', 'desc': 'set image for the resource under the cursor',
      \   'run': {kbuf -> kube#actions#run(kbuf, 'set_image')}},
      \ 'exec': {'lhs': 'gs', 'desc': 'exec into the resource under the cursor', 'run': {kbuf -> kube#actions#run(kbuf, 'exec')}},
      \ 'operations': {'desc': 'all operations on the resource, or on a visual selection'},
      \ }

let s:HELP = [
      \ '',
      \ 'Built-in keys that also work',
      \ "  <C-]>    jump to what the cell under the cursor refers to: NAMESPACE",
      \ '           filters the list, NODE opens the node, an event''s OBJECT the',
      \ '           object, a namespace row lists its pods, a resource type lists',
      \ '           it, else the YAML',
      \ '  <C-t>    jump back, <C-w>] opens the jump in a split',
      \ '  ]d [d    next / previous unhealthy resource, <C-w>d shows why',
      \ '  gx       open the port forward URL under the cursor',
      \ '',
      \ 'Editing, :w applies after confirming, :w! without confirming',
      \ '  lists    delete lines to delete the resources, uninstall the releases',
      \ '  YAML     (gd) shows `kubectl diff` before applying',
      \ '  secrets  (<CR> on a secret) decoded `key: "value"` lines',
      \ '',
      \ 'Commands',
      \ '  :Kube get {kind} [namespace={ns}] [selector={labels}]',
      \ '  :Kube delete {kind} {name} [namespace={ns}]',
      \ '  :Kube context [{context}]',
      \ '  :Kube[!] apply / :Kube diff   the current buffer as a manifest',
      \ '  :Kube portforwards            all port forwards',
      \ '',
      \ 'Buffer names',
      \ '  kube://[context/{context}/][namespaces/{ns}/]{kind}[/{name}[/{subresource}]]',
      \ '  Without context/{context}/ the current context is used and the buffer',
      \ '  stays bound to it, e.g. :e kube://deployments',
      \ '  :e kube:// lists the resource types, :e kube://helm the Helm releases',
      \ '',
      \ 'More in :help kube.nvim',
      \ ]

" ---------------------------------------------------------------------------
" Names

" Parse a buffer name, see kube#utils#buf_name().
function! kube#provider#parse(name) abort
  let parts = resource#parse(a:name)
  let segments = parts.segments

  let context = ''
  if get(segments, 0, '') ==# 'context' && len(segments) >= 3
    let context = resource#uri_decode(segments[1])
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

  return {
        \ 'context': context,
        \ 'namespace': namespace,
        \ 'resource_kind': kind,
        \ 'resource_name': name,
        \ 'subresource_kind': subresource,
        \ 'params': parts.params,
        \ 'data': v:null,
        \ }
endfunction

" The name of the buffer {name} is an alias of, itself if none: without
" context/{context}/ it is pinned to the current context, so that the buffer
" keeps operating on the same cluster after the context is switched; ctx is
" short for context, ns for namespaces, helm for helm-releases; no kind is the
" resource types, api-resources. Throws without a current context.
function! kube#provider#canonical(name) abort
  if a:name ==# 'kube://portforwards'
    return a:name
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
      throw 'No current kubectl context'
    endif
    let context = 'context/' . resource#uri_encode(current) . '/'
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
  return 'kube://' . context . rest
endfunction

" ---------------------------------------------------------------------------
" Items

" Identity of the item of a row that survives reloads, so that the cursor can
" stay on the same row.
function! kube#provider#identity(item) abort
  if has_key(a:item, 'metadata')
    return join([get(a:item, 'kind', ''), kube#utils#get(a:item.metadata, 'namespace', ''), kube#utils#get(a:item.metadata, 'name', '')], '/')
  endif
  if has_key(a:item, 'local_port')
    return a:item.id . ':' . a:item.local_port
  endif
  " Helm releases of the same name in different namespaces
  if has_key(a:item, 'namespace')
    return a:item.namespace . '/' . a:item.name
  endif
  return get(a:item, 'name', '')
endfunction

" How messages name an item: {resource type}/{name} for resources.
function! kube#provider#label(item) abort
  return has_key(a:item, 'metadata') ? kube#utils#resource_type(a:item) . '/' . a:item.metadata.name : get(a:item, 'name', '')
endfunction

" ---------------------------------------------------------------------------
" Keymaps

" What the cell refers to, mostly the YAML.
function! s:show_yaml(kbuf) abort
  let target = resource#tag(a:kbuf)
  if empty(target)
    call kube#actions#run(a:kbuf, 'show_yaml')
  else
    call resource#open(target)
  endif
endfunction

" Describe the resource of the cursor line, explain a resource type, show the
" status of a Helm release.
function! s:describe(kbuf) abort
  let k = a:kbuf
  let item = resource#item(k)
  if type(item) != v:t_dict
    return
  endif
  let kind = get(item, 'kind', '')
  let Show = function('s:show_float', [k.bufnr])
  let OnError = {err -> resource#notify(err, 'error')}
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
    call resource#float(split(trim(a:result), "\n"))
  endif
endfunction

" Go to the owner of the resource of the cursor line, or of the buffer's
" resource: the controller first.
function! s:owner(kbuf) abort
  let k = a:kbuf
  if empty(k.resource_name) || !empty(k.subresource_kind)
    let item = resource#item(k)
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
    call resource#notify('No owner', 'warn')
    return
  endif
  call kube#utils#open({'context': a:kbuf.context, 'namespace': kube#utils#get(a:resource.metadata, 'namespace', ''),
        \ 'kind': kube#utils#resource_type(owner), 'name': owner.name, 'params': {'output': 'yaml'}})
endfunction
