" Operations on the resources of rows, offered by the operations keymap (gra),
" on the row under the cursor or the rows of a visual selection. An operation
" is a dict: title, run (a funcref without arguments).

let s:LOGS = ['Pod', 'Deployment', 'StatefulSet', 'DaemonSet', 'ReplicaSet', 'Job']
let s:SCALABLE = ['Deployment', 'StatefulSet', 'ReplicaSet']
let s:ROLLOUT = ['Deployment', 'StatefulSet', 'DaemonSet']
let s:RELATED_EVENTS = ['Deployment', 'StatefulSet', 'DaemonSet', 'ReplicaSet', 'Job', 'Service']

function! s:op(title, Run) abort
  return {'title': a:title, 'run': a:Run}
endfunction

" Run {Call}(item) for every item, it returns the job of the item, then
" reload the buffer.
function! s:run_all(kbuf, items, Call) abort
  call resource#run(a:kbuf, a:items, a:Call)
endfunction

" Run {Call} on all {items} once confirmed, the prompt is {verb} {targets}.
function! s:confirmed(kbuf, items, verb, targets, Call) abort
  call resource#run(a:kbuf, a:items, a:Call, a:verb . ' ' . a:targets)
endfunction

function! s:confirmed_resources(kbuf, resources, verb, Call) abort
  call s:confirmed(a:kbuf, a:resources, a:verb, resource#describe(a:kbuf, a:resources), a:Call)
endfunction

function! s:args(resource) abort
  return [kube#utils#resource_type(a:resource), a:resource.metadata.name, kube#utils#get(a:resource.metadata, 'namespace', '')]
endfunction

" Operations on a container of the buffer's pod.
function! kube#operations#for_container(kbuf, container) abort
  let Logs = function('kube#actions#container_logs', [a:kbuf, a:container])
  return [
        \ s:op('Show logs', function(Logs, [{}])),
        \ s:op('Follow logs', function(Logs, [{'follow': v:true}])),
        \ s:op('Show logs of the previous instance', function(Logs, [{'previous': v:true}])),
        \ s:op('Exec', function(kube#actions#get('container', 'exec'), [a:kbuf, a:container])),
        \ s:op('Forward port', function(kube#actions#get('container', 'forward_port'), [a:kbuf, a:container])),
        \ ]
endfunction

" Operations on a resource type of the api-resources buffer.
function! s:api_resource_operations(kbuf, type) abort
  let namespace = a:type.namespaced ? a:kbuf.namespace : ''
  let operations = [s:op('List', function(kube#actions#get('apiresource', 'drill_down_resource'), [a:kbuf, a:type]))]
  if !empty(namespace) && namespace !=# 'all'
    call add(operations, s:op('List in all namespaces', function('kube#utils#open', [{'context': a:kbuf.context, 'kind': a:type.name}])))
  endif
  call add(operations, s:op('Show events', function('kube#utils#open', [{
        \ 'context': a:kbuf.context,
        \ 'namespace': namespace,
        \ 'kind': 'events',
        \ 'params': {'field-selector': 'involvedObject.kind=' . a:type.object_kind},
        \ }])))
  return operations
endfunction

function! s:stop_forwards(kbuf, forwards, yes) abort
  if !a:yes
    return
  endif
  for forward in a:forwards
    call kube#portforward#stop(forward.id, forward.local_port)
  endfor
  call resource#load(a:kbuf)
endfunction

" Operations on port forward rows, of a resource or of kube://portforwards.
function! s:portforward_operations(kbuf, forwards) abort
  let operations = []
  if len(a:forwards) == 1
    let forward = a:forwards[0]
    let pf = forward.portforward
    call add(operations, s:op('Open in browser', function('kube#ui#open', ['http://localhost:' . forward.local_port])))
    call add(operations, s:op(printf('Go to %s/%s', pf.resource_type, pf.name), function('kube#utils#open', [{
          \ 'context': pf.context,
          \ 'namespace': pf.namespace,
          \ 'kind': pf.resource_type,
          \ 'name': pf.name,
          \ 'params': {'output': 'yaml'},
          \ }])))
  endif
  let ports = join(map(copy(a:forwards), 'v:val.local_port'), ', ')
  let title = len(a:forwards) == 1 ? 'Stop' : printf('Stop %d port forwards', len(a:forwards))
  call add(operations, s:op(title, {-> resource#confirm(printf('Stop the port forwards of local ports %s?', ports),
        \ function('s:stop_forwards', [a:kbuf, a:forwards]))}))
  return operations
endfunction

function! s:rollback(kbuf, revision, item) abort
  let release = get(a:item, 'release', a:item.name)
  return helm#cli#rollback(a:kbuf.context, release, a:item.namespace, a:revision, v:null, v:null)
endfunction

function! s:uninstall(kbuf, release) abort
  return helm#cli#uninstall(a:kbuf.context, a:release.name, a:release.namespace, v:null, v:null)
endfunction

" Operations on Helm releases, rows of helm-releases, or on the revisions of
" the history of a release.
function! s:helm_operations(kbuf, items) abort
  let Open = function('kube#actions#open_release', [a:kbuf])
  if a:kbuf.subresource_kind ==# 'history'
    if len(a:items) != 1
      return []
    endif
    let revision = a:items[0]
    let release = {'name': revision.release, 'namespace': revision.namespace}
    let target = printf('helm release %s/%s to revision %d', release.namespace, release.name, revision.revision)
    return [
          \ s:op(printf('Rollback to revision %d', revision.revision),
          \   function('s:confirmed', [a:kbuf, a:items, 'Roll back', target, function('s:rollback', [a:kbuf, revision.revision])])),
          \ s:op(printf('Show manifest of revision %d', revision.revision), function(Open, [release, 'manifest', {'revision': revision.revision}])),
          \ s:op(printf('Show values of revision %d', revision.revision), function(Open, [release, 'values', {'revision': revision.revision}])),
          \ ]
  endif

  let operations = []
  if len(a:items) == 1
    let release = a:items[0]
    for [title, subresource, params] in [
          \ ['Show manifest', 'manifest', {}],
          \ ['Show values', 'values', {}],
          \ ['Show all values', 'values', {'all': v:true}],
          \ ['Show notes', 'notes', {}],
          \ ['Show status', '', {}],
          \ ['Show history', 'history', {}],
          \ ]
      call add(operations, s:op(title, function(Open, [release, subresource, params])))
    endfor
    if get(release, 'revision', 0) > 1
      call add(operations, s:op('Rollback to the previous revision', function('s:confirmed', [a:kbuf, a:items, 'Roll back',
            \ printf('helm release %s/%s', release.namespace, release.name), function('s:rollback', [a:kbuf, v:null])])))
    endif
  endif
  let names = join(map(copy(a:items), 'v:val.namespace . "/" . v:val.name'), ', ')
  call add(operations, s:op(len(a:items) == 1 ? 'Uninstall' : printf('Uninstall %d releases', len(a:items)),
        \ function('s:confirmed', [a:kbuf, a:items, 'Uninstall', 'helm release ' . names, function('s:uninstall', [a:kbuf])])))
  return operations
endfunction

function! s:show_events(kbuf, resource) abort
  let kind = a:resource.kind
  " Workloads and services: also the events of the pods they select
  if index(s:RELATED_EVENTS, kind) >= 0
    let params = {'for': kube#utils#resource_type(a:resource) . '/' . a:resource.metadata.name}
  else
    let params = {'field-selector': printf('involvedObject.kind=%s,involvedObject.name=%s', kind, a:resource.metadata.name)}
  endif
  call kube#utils#open({'context': a:kbuf.context, 'namespace': a:resource.metadata.namespace, 'kind': 'events', 'params': params})
endfunction

function! s:logs_since(kbuf, resource) abort
  call resource#input({'prompt': 'Since (e.g. 30s, 5m, 1h): ', 'default': '1h'},
        \ {since -> since is v:null ? 0 : kube#actions#open_resource(a:kbuf, a:resource, 'logs', {'since': since})})
endfunction

function! s:trigger(kbuf, resource) abort
  " Job names are at most 63 characters, as they are label values
  let job = printf('%s-manual-%d', a:resource.metadata.name[0:44], localtime())
  call s:confirmed_resources(a:kbuf, [a:resource], 'Trigger',
        \ {r -> kube#kubectl#create_job(a:kbuf.context, r.metadata.name, r.metadata.namespace, job, v:null, v:null)})
endfunction

function! s:undo(kbuf, resource) abort
  call s:confirmed_resources(a:kbuf, [a:resource], 'Undo the rollout of',
        \ {r -> call('kube#kubectl#rollout', [a:kbuf.context, 'undo'] + s:args(r) + [v:null, v:null])})
endfunction

function! s:single_operations(kbuf, resource) abort
  let kind = a:resource.kind
  let k = a:kbuf
  let r = a:resource
  let Open = function('kube#actions#open_resource', [k, r])
  let operations = [
        \ s:op('Open', function('s:run_action', [k, r, 'drill_down_resource'])),
        \ s:op('Describe', function(Open, ['', {}])),
        \ s:op('Go to YAML', function(Open, ['', {'output': 'yaml'}])),
        \ s:op('Show events', function('s:show_events', [k, r])),
        \ ]

  if index(s:LOGS, kind) >= 0
    call add(operations, s:op('Show logs', function(Open, ['logs', {}])))
    call add(operations, s:op('Follow logs', function(Open, ['logs', {'follow': v:true}])))
    call add(operations, s:op('Show logs of all containers', function(Open, ['logs', {'all-containers': v:true}])))
    if kind ==# 'Pod'
      call add(operations, s:op('Show logs of the previous instance', function(Open, ['logs', {'previous': v:true}])))
    endif
    call add(operations, s:op('Show logs since…', function('s:logs_since', [k, r])))
  endif

  for [action, title] in [['exec', 'Exec'], ['forward_port', 'Forward port'], ['port_forward', 'Show port forwards'], ['set_image', 'Set image']]
    if kube#actions#get(tolower(kind), action) isnot v:null
      call add(operations, s:op(title, function('s:run_action', [k, r, action])))
    endif
  endfor

  if index(s:ROLLOUT, kind) >= 0
    call add(operations, s:op('Undo rollout', function('s:undo', [k, r])))
    call add(operations, s:op('Rollout history', function(Open, ['history', {}])))
  endif
  if kind ==# 'Pod'
    call add(operations, s:op('Debug (ephemeral container)', function('kube#exec#prompt_debug', [k.context, r])))
  endif
  if kind ==# 'CronJob'
    call add(operations, s:op('Trigger now', function('s:trigger', [k, r])))
  endif
  if kind ==# 'Secret'
    call add(operations, s:op('Decode secret', function(Open, ['data', {}])))
  endif
  return operations
endfunction

function! s:run_action(kbuf, resource, name) abort
  call kube#actions#get(tolower(a:resource.kind), a:name)(a:kbuf, a:resource)
endfunction

function! s:all(resources, kinds) abort
  return empty(filter(copy(a:resources), 'index(a:kinds, v:val.kind) < 0'))
endfunction

function! s:scale(kbuf, resources) abort
  let current = kube#utils#dig(a:resources[0], 'spec.replicas', 1)
  call resource#input({'prompt': 'Replicas: ', 'default': string(current)}, function('s:on_replicas', [a:kbuf, a:resources]))
endfunction

function! s:on_replicas(kbuf, resources, input) abort
  let replicas = kube#edits#parse_replicas(a:input)
  if replicas < 0
    if a:input isnot v:null
      call resource#notify('Invalid number of replicas: ' . a:input, 'error')
    endif
    return
  endif
  call s:run_all(a:kbuf, a:resources,
        \ {r -> call('kube#kubectl#scale', [a:kbuf.context] + s:args(r) + [replicas, v:null, v:null])})
endfunction

function! s:node(kbuf, resources, verb) abort
  let Call = {r -> kube#kubectl#node(a:kbuf.context, a:verb, r.metadata.name, v:null, v:null)}
  if a:verb ==# 'drain'
    call s:confirmed_resources(a:kbuf, a:resources, 'Drain', Call)
  else
    call s:run_all(a:kbuf, a:resources, Call)
  endif
endfunction

" Operations on all {resources} at once.
function! s:bulk_operations(kbuf, resources) abort
  let k = a:kbuf
  let operations = []
  if s:all(a:resources, s:SCALABLE)
    call add(operations, s:op('Scale…', function('s:scale', [k, a:resources])))
  endif
  if s:all(a:resources, s:ROLLOUT)
    call add(operations, s:op('Restart', function('s:confirmed_resources', [k, a:resources, 'Restart',
          \ {r -> call('kube#kubectl#rollout', [k.context, 'restart'] + s:args(r) + [v:null, v:null])}])))
  endif
  if s:all(a:resources, ['Node'])
    for verb in ['cordon', 'uncordon', 'drain']
      call add(operations, s:op(toupper(verb[0]) . verb[1:], function('s:node', [k, a:resources, verb])))
    endfor
  endif
  call add(operations, s:op('Delete', function('s:confirmed_resources', [k, a:resources, 'Delete',
        \ {r -> call('kube#kubectl#delete', [k.context] + s:args(r) + [v:null, v:null])}])))
  return operations
endfunction

" The operations on {items} of rows of the buffer.
function! kube#operations#for_items(kbuf, items) abort
  let k = a:kbuf
  if empty(a:items)
    return []
  elseif k.subresource_kind ==# 'containers'
    return len(a:items) == 1 ? kube#operations#for_container(k, a:items[0]) : []
  elseif k.resource_kind ==# 'api-resources'
    return len(a:items) == 1 ? s:api_resource_operations(k, a:items[0]) : []
  elseif k.resource_kind ==# 'portforwards' || k.subresource_kind ==# 'portforward'
    return s:portforward_operations(k, a:items)
  elseif k.resource_kind ==# 'helm-releases'
    return s:helm_operations(k, a:items)
  endif

  let resources = filter(copy(a:items), 'has_key(v:val, "metadata") && has_key(v:val, "kind")')
  if len(resources) != len(a:items)
    return []
  endif
  if len(resources) == 1
    return s:single_operations(k, resources[0]) + s:bulk_operations(k, resources)
  endif
  " Name the targets of bulk operations
  return map(s:bulk_operations(k, resources), 'extend(v:val, {"title": printf("%s %d resources", substitute(v:val.title, "…$", "", ""), len(resources))})')
endfunction
