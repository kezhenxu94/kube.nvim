" Load the content of kube buffers, by the kind of view of their name.
" Renderers return the job loading the buffer, {} if none.

function! kube#render#load(kbuf) abort
  let k = a:kbuf
  if k.resource_kind ==# 'helm-releases'
    return helm#render#load(k)
  endif

  if empty(k.resource_name)
    if k.resource_kind ==# 'events' && has_key(k.params, 'for')
      return s:related_events(k)
    elseif k.resource_kind ==# 'pods' && has_key(k.params, 'using')
      return s:pods_using(k)
    elseif k.resource_kind ==# 'api-resources'
      return s:api_resources(k)
    elseif k.resource_kind ==# 'portforwards'
      " From the registry instead of kubectl
      call kube#table#render(k, kube#format#get('portforwards'), v:null, v:null)
      return {}
    endif
    return kube#table#load(k)
  endif

  if empty(k.subresource_kind)
    let output = get(k.params, 'output', '')
    if type(output) == v:t_string && output ==# 'yaml'
      return s:yaml(k)
    elseif !empty(output)
      call kube#ui#notify('Unsupported output type: ' . kube#utils#to_string(output), 'error')
      return {}
    endif
    return s:describe(k)
  endif

  if k.subresource_kind ==# 'logs'
    return kube#logs#load(k)
  elseif k.subresource_kind ==# 'history'
    return s:history(k)
  elseif k.subresource_kind ==# 'data'
    return s:secret_data(k)
  endif
  " Tables of the parent resource: containers, portforward
  return kube#table#load(k)
endfunction

" kubectl describe of the buffer's resource.
function! s:describe(kbuf) abort
  let k = a:kbuf
  return kube#kubectl#describe(k.context, k.resource_kind, k.resource_name, k.namespace,
        \ function('s:set_lines', [k, 0]), kube#buffer#on_error(k))
endfunction

" kubectl rollout history of the buffer's workload.
function! s:history(kbuf) abort
  let k = a:kbuf
  return kube#kubectl#rollout(k.context, 'history', k.resource_kind, k.resource_name, k.namespace,
        \ function('s:set_lines', [k, 1]), kube#buffer#on_error(k))
endfunction

function! s:set_lines(kbuf, trim, result) abort
  if a:result isnot v:null && bufloaded(a:kbuf.bufnr)
    call kube#buffer#set_lines(a:kbuf, split(a:trim ? trim(a:result) : a:result, "\n", 1))
  endif
endfunction

" The YAML of the buffer's resource, editable: :w applies it.
function! s:yaml(kbuf) abort
  let k = a:kbuf
  call setbufvar(k.bufnr, '&filetype', 'yaml')
  return kube#buffer#track(k, kube#kubectl#get_resource_yaml(k.context, k.resource_kind, k.resource_name, k.namespace,
        \ function('s:show_yaml', [k]), kube#buffer#on_error(k)))
endfunction

function! s:show_yaml(kbuf, yaml) abort
  if !bufloaded(a:kbuf.bufnr)
    return
  endif
  if a:yaml isnot v:null
    call kube#buffer#set_lines(a:kbuf, split(a:yaml, "\n", 1), 1)
  elseif getbufline(a:kbuf.bufnr, 1, '$') == ['']
    " Nothing loaded: nothing to edit and apply
    call setbufvar(a:kbuf.bufnr, '&modifiable', 0)
  endif
endfunction

" The decoded data of the buffer's secret, see kube#secret.
function! s:secret_data(kbuf) abort
  let k = a:kbuf
  return kube#buffer#track(k, kube#kubectl#get(k.context, k.resource_kind, k.resource_name, k.namespace, {},
        \ function('s:show_secret', [k]), kube#buffer#on_error(k)))
endfunction

function! s:show_secret(kbuf, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let secret = json_decode(a:result)
  let a:kbuf.data = secret
  call setbufvar(a:kbuf.bufnr, '&filetype', 'yaml')
  call kube#buffer#set_lines(a:kbuf, kube#secret#to_lines(kube#utils#get(secret, 'data', {})), 1)
endfunction

" Parse the kubectl api-resources table by the columns of its header,
" SHORTNAMES may be empty.
function! s:parse_api_resources(output) abort
  let lines = split(a:output, "\n")
  let header = empty(lines) ? '' : remove(lines, 0)
  let columns = []
  let start = match(header, '\S\+')
  while start >= 0
    let column = matchstr(header, '\S\+', start)
    call add(columns, {'start': start, 'key': tolower(column)})
    let start = match(header, '\S\+', start + len(column))
  endwhile

  let resources = []
  for line in lines
    let resource = {}
    for i in range(len(columns))
      let end = i + 1 < len(columns) ? columns[i + 1].start : len(line)
      let resource[columns[i].key] = trim(strpart(line, columns[i].start, end - columns[i].start))
    endfor
    call add(resources, resource)
  endfor
  return resources
endfunction

" The resource types of the cluster, to pick one to list.
function! s:api_resources(kbuf) abort
  return kube#kubectl#api_resources(a:kbuf.context, function('s:show_api_resources', [a:kbuf]), kube#buffer#on_error(a:kbuf))
endfunction

function! s:show_api_resources(kbuf, result, code, stderr) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  call kube#table#render(a:kbuf, kube#format#get('api-resources'), s:parse_api_resources(a:result), v:null)
  " Exits with 1 when some API groups fail, e.g. an unavailable metrics
  " server, listing the others
  if a:code != 0
    let OnError = kube#buffer#on_error(a:kbuf)
    call OnError(a:stderr)
  endif
endfunction

" The kinds of the resources pods use, by their kind.
let s:USED_KINDS = {
      \ 'ConfigMap': 'configmap',
      \ 'Secret': 'secret',
      \ 'PersistentVolumeClaim': 'persistentvolumeclaim',
      \ 'ServiceAccount': 'serviceaccount',
      \ 'Node': 'node',
      \ }

function! s:use(used, kind, name) abort
  if !empty(a:name)
    let a:used[a:kind . '/' . a:name] = 1
  endif
endfunction

" The {kind}/{name} of the resources a pod uses: {kind/name: 1}.
function! s:used_by(pod) abort
  let spec = kube#utils#get(a:pod, 'spec', {})
  let used = {}
  let Use = function('s:use', [used])
  let G = function('kube#utils#dig')

  call Use('node', G(spec, 'nodeName', ''))
  call Use('serviceaccount', G(spec, 'serviceAccountName', ''))
  for secret in kube#utils#list(spec, 'imagePullSecrets')
    call Use('secret', G(secret, 'name', ''))
  endfor
  for volume in kube#utils#list(spec, 'volumes')
    call Use('configmap', G(volume, 'configMap.name', ''))
    call Use('secret', G(volume, 'secret.secretName', ''))
    call Use('persistentvolumeclaim', G(volume, 'persistentVolumeClaim.claimName', ''))
    for source in G(volume, 'projected.sources', [])
      call Use('configmap', G(source, 'configMap.name', ''))
      call Use('secret', G(source, 'secret.name', ''))
    endfor
  endfor
  for containers in ['initContainers', 'containers', 'ephemeralContainers']
    for container in kube#utils#list(spec, containers)
      for env in kube#utils#list(container, 'env')
        call Use('configmap', G(env, 'valueFrom.configMapKeyRef.name', ''))
        call Use('secret', G(env, 'valueFrom.secretKeyRef.name', ''))
      endfor
      for from in kube#utils#list(container, 'envFrom')
        call Use('configmap', G(from, 'configMapRef.name', ''))
        call Use('secret', G(from, 'secretRef.name', ''))
      endfor
    endfor
  endfor
  return used
endfunction

" The pods using a resource: kube://.../pods?using={kind}/{name}.
function! s:pods_using(kbuf) abort
  let k = a:kbuf
  let using = k.params.using
  " The pods of a node are in all namespaces: only ask for those
  let node = matchstr(using, '^node/\zs.\+$')
  let params = empty(node) ? {} : {'field-selector': 'spec.nodeName=' . node}
  return kube#kubectl#get(k.context, 'pods', '', k.namespace, params, function('s:show_pods_using', [k, using]), kube#buffer#on_error(k))
endfunction

function! s:show_pods_using(kbuf, using, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let pods = filter(json_decode(a:result).items, 'has_key(s:used_by(v:val), a:using)')
  call kube#table#render(a:kbuf, kube#format#get('pods'), {'items': pods}, v:null)
endfunction

" The label selector of a workload (spec.selector.matchLabels) or service
" (spec.selector): key=value,..., '' if none.
function! s:label_selector(object) abort
  let selector = kube#utils#dig(a:object, 'spec.selector', v:null)
  if type(selector) != v:t_dict
    return ''
  endif
  if has_key(selector, 'matchLabels') || has_key(selector, 'matchExpressions')
    let selector = kube#utils#get(selector, 'matchLabels', {})
  endif
  return join(sort(map(items(selector), 'v:val[0] . "=" . v:val[1]')), ',')
endfunction

" Keep the buffer loading until the last call of the chain.
function! s:track(kbuf, job) abort
  if !empty(a:job)
    call kube#buffer#track(a:kbuf, a:job)
    let a:kbuf.loading_job = a:job
  endif
endfunction

" The events of a workload or service and of the pods and replica sets it
" selects: kube://.../events?for={type}/{name}, field selectors only match a
" single object.
function! s:related_events(kbuf) abort
  let k = a:kbuf
  let [resource_type, name] = matchlist(k.params.for, '^\(.\{-}\)/\(.\+\)$')[1:2]
  return kube#kubectl#get(k.context, resource_type, name, k.namespace, {}, function('s:on_related', [k, name]), kube#buffer#on_error(k))
endfunction

function! s:on_related(kbuf, name, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let object = json_decode(a:result)
  let involved = {}
  let involved[object.kind . '/' . a:name] = 1
  let selector = s:label_selector(object)
  if empty(selector)
    call s:load_events(a:kbuf, involved)
    return
  endif
  call s:track(a:kbuf, kube#kubectl#get(a:kbuf.context, 'pods,replicasets', '', a:kbuf.namespace, {'selector': selector},
        \ function('s:on_owned', [a:kbuf, involved]), kube#buffer#on_error(a:kbuf)))
endfunction

function! s:on_owned(kbuf, involved, result) abort
  if a:result is v:null
    return
  endif
  for item in json_decode(a:result).items
    let a:involved[item.kind . '/' . item.metadata.name] = 1
  endfor
  call s:load_events(a:kbuf, a:involved)
endfunction

function! s:load_events(kbuf, involved) abort
  call s:track(a:kbuf, kube#kubectl#get(a:kbuf.context, 'events', '', a:kbuf.namespace, {},
        \ function('s:show_events', [a:kbuf, a:involved]), kube#buffer#on_error(a:kbuf)))
endfunction

function! s:show_events(kbuf, involved, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let events = filter(json_decode(a:result).items,
        \ 'has_key(a:involved, kube#utils#dig(v:val, "involvedObject.kind", "") . "/" . kube#utils#dig(v:val, "involvedObject.name", ""))')
  call kube#table#render(a:kbuf, kube#format#get('events'), {'items': events}, v:null)
endfunction
