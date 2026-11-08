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
      call kube#render#table(k, kube#format#get('portforwards'), v:null, v:null)
      return {}
    endif
    return s:list(k)
  endif

  if empty(k.subresource_kind)
    let output = get(k.params, 'output', '')
    if type(output) == v:t_string && output ==# 'yaml'
      return s:yaml(k)
    elseif !empty(output)
      call resource#notify('Unsupported output type: ' . resource#to_string(output), 'error')
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
  return s:list(k)
endfunction

" kubectl describe of the buffer's resource.
function! s:describe(kbuf) abort
  let k = a:kbuf
  return kube#kubectl#describe(k.context, k.resource_kind, k.resource_name, k.namespace,
        \ function('s:set_lines', [k, 0]), function('resource#error', [k]))
endfunction

" kubectl rollout history of the buffer's workload.
function! s:history(kbuf) abort
  let k = a:kbuf
  return kube#kubectl#rollout(k.context, 'history', k.resource_kind, k.resource_name, k.namespace,
        \ function('s:set_lines', [k, 1]), function('resource#error', [k]))
endfunction

function! s:set_lines(kbuf, trim, result) abort
  if a:result isnot v:null && bufloaded(a:kbuf.bufnr)
    call resource#set_lines(a:kbuf, split(a:trim ? trim(a:result) : a:result, "\n", 1))
  endif
endfunction

" The YAML of the buffer's resource, editable: :w applies it.
function! s:yaml(kbuf) abort
  let k = a:kbuf
  call setbufvar(k.bufnr, '&filetype', 'yaml')
  return kube#kubectl#get_resource_yaml(k.context, k.resource_kind, k.resource_name, k.namespace,
        \ function('s:show_yaml', [k]), function('resource#error', [k]))
endfunction

function! s:show_yaml(kbuf, yaml) abort
  if !bufloaded(a:kbuf.bufnr)
    return
  endif
  if a:yaml isnot v:null
    call resource#set_lines(a:kbuf, split(a:yaml, "\n", 1), {'modifiable': 1})
  elseif getbufline(a:kbuf.bufnr, 1, '$') == ['']
    " Nothing loaded: nothing to edit and apply
    call setbufvar(a:kbuf.bufnr, '&modifiable', 0)
  endif
endfunction

" The decoded data of the buffer's secret, see kube#secret.
function! s:secret_data(kbuf) abort
  let k = a:kbuf
  return kube#kubectl#get(k.context, k.resource_kind, k.resource_name, k.namespace, {},
        \ function('s:show_secret', [k]), function('resource#error', [k]))
endfunction

function! s:show_secret(kbuf, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let secret = json_decode(a:result)
  let a:kbuf.data = secret
  call setbufvar(a:kbuf.bufnr, '&filetype', 'yaml')
  call resource#set_lines(a:kbuf, kube#secret#to_lines(kube#utils#get(secret, 'data', {})), {'modifiable': 1})
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
  return kube#kubectl#api_resources(a:kbuf.context, function('s:show_api_resources', [a:kbuf]), function('resource#error', [a:kbuf]))
endfunction

function! s:show_api_resources(kbuf, result, code, stderr) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  call kube#render#table(a:kbuf, kube#format#get('api-resources'), s:parse_api_resources(a:result), v:null)
  " Exits with 1 when some API groups fail, e.g. an unavailable metrics
  " server, listing the others
  if a:code != 0
    call resource#error(a:kbuf, a:stderr)
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
  return kube#kubectl#get(k.context, 'pods', '', k.namespace, params, function('s:show_pods_using', [k, using]), function('resource#error', [k]))
endfunction

function! s:show_pods_using(kbuf, using, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let pods = filter(json_decode(a:result).items, 'has_key(s:used_by(v:val), a:using)')
  call kube#render#table(a:kbuf, kube#format#get('pods'), {'items': pods}, v:null)
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
  call resource#track(a:kbuf, a:job)
endfunction

" The events of a workload or service and of the pods and replica sets it
" selects: kube://.../events?for={type}/{name}, field selectors only match a
" single object.
function! s:related_events(kbuf) abort
  let k = a:kbuf
  let [resource_type, name] = matchlist(k.params.for, '^\(.\{-}\)/\(.\+\)$')[1:2]
  return kube#kubectl#get(k.context, resource_type, name, k.namespace, {}, function('s:on_related', [k, name]), function('resource#error', [k]))
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
        \ function('s:on_owned', [a:kbuf, involved]), function('resource#error', [a:kbuf])))
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
        \ function('s:show_events', [a:kbuf, a:involved]), function('resource#error', [a:kbuf])))
endfunction

function! s:show_events(kbuf, involved, result) abort
  if a:result is v:null || !bufloaded(a:kbuf.bufnr)
    return
  endif
  let events = filter(json_decode(a:result).items,
        \ 'has_key(a:involved, kube#utils#dig(v:val, "involvedObject.kind", "") . "/" . kube#utils#dig(v:val, "involvedObject.name", ""))')
  call kube#render#table(a:kbuf, kube#format#get('events'), {'items': events}, v:null)
endfunction

" ---------------------------------------------------------------------------
" Lists

" The formatter of the buffer's list, see kube#format.
function! kube#render#formatter(kbuf) abort
  return kube#format#get(empty(a:kbuf.subresource_kind) ? a:kbuf.resource_kind : a:kbuf.subresource_kind)
endfunction

" Contexts whose cluster has no metrics API, not asked again
let s:metrics_unavailable = {}

" CPU and memory usage by namespace/name, from kubectl top --no-headers.
function! s:parse_metrics(output, kind, namespace) abort
  let metrics = {}
  for line in split(a:output, "\n")
    let fields = split(line)
    if a:kind ==# 'nodes'
      " NAME CPU(cores) CPU(%) MEMORY(bytes) MEMORY(%)
      let metrics['/' . fields[0]] = [fields[1], fields[3]]
    elseif tolower(a:namespace) ==# 'all'
      let metrics[fields[0] . '/' . fields[1]] = [fields[2], fields[3]]
    else
      let metrics[a:namespace . '/' . fields[0]] = [fields[1], fields[2]]
    endif
  endfor
  return metrics
endfunction

" Load a list with kubectl get, and the metrics of its resources when they have.
function! s:list(kbuf) abort
  let k = a:kbuf
  let formatter = kube#render#formatter(k)
  let kind = empty(k.resource_name) ? get(formatter, 'metrics', '') : ''
  let with_metrics = !empty(kind) && !has_key(s:metrics_unavailable, k.context)

  " Render once the resources and, if asked, their metrics are loaded
  let state = {'kbuf': k, 'formatter': formatter, 'pending': with_metrics ? 2 : 1, 'data': v:null, 'metrics': v:null}
  let job = kube#kubectl#get(k.context, k.resource_kind, k.resource_name, k.namespace, k.params,
        \ function('s:on_data', [state]), function('resource#error', [k]))
  if empty(job) || !with_metrics
    return job
  endif
  let top = kube#kubectl#top(k.context, kind, k.namespace, get(k.params, 'selector', ''),
        \ function('s:on_metrics', [state, kind]), function('s:on_metrics_error', [k.context]))
  if empty(top)
    call s:loaded(state)
    return job
  endif
  return [job, top]
endfunction

function! s:loaded(state) abort
  let a:state.pending -= 1
  if a:state.pending == 0 && a:state.data isnot v:null && bufloaded(a:state.kbuf.bufnr)
    call kube#render#table(a:state.kbuf, a:state.formatter, a:state.data, a:state.metrics)
  endif
endfunction

function! s:on_data(state, result) abort
  if a:result isnot v:null && bufloaded(a:state.kbuf.bufnr)
    let a:state.data = json_decode(a:result)
  endif
  call s:loaded(a:state)
endfunction

function! s:on_metrics(state, kind, result) abort
  if a:result isnot v:null
    let a:state.metrics = s:parse_metrics(a:result, a:kind, a:state.kbuf.namespace)
  endif
  call s:loaded(a:state)
endfunction

function! s:on_metrics_error(context, err) abort
  if stridx(a:err, 'Metrics API not available') >= 0
    let s:metrics_unavailable[a:context] = 1
  endif
endfunction

" Insert the CPU and memory usage columns before AGE, returns the headers.
function! s:add_metrics(headers, rows, metrics) abort
  let at = index(a:headers, 'AGE')
  let at = at < 0 ? len(a:headers) : at
  for row in a:rows
    let usage = get(a:metrics, kube#utils#get(row.item.metadata, 'namespace', '') . '/' . row.item.metadata.name, ['', ''])
    call extend(row.row, usage, at)
  endfor
  return extend(copy(a:headers), ['CPU', 'MEMORY'], at)
endfunction

" Render the rows of {data} (the decoded output) with {formatter} as a table.
" {metrics}: the usage of the resources, adds CPU and MEMORY columns, or v:null.
function! kube#render#table(kbuf, formatter, data, metrics) abort
  let a:kbuf.data = a:data
  let rows = a:formatter.fn(a:data, a:kbuf)
  let headers = a:formatter.headers
  if a:metrics isnot v:null
    let headers = s:add_metrics(headers, rows, a:metrics)
  endif
  call resource#render(a:kbuf, {'headers': headers, 'rows': rows, 'empty': get(a:formatter, 'empty', 'No resources found'),
        \ 'editable': get(a:formatter, 'editable', {})})
endfunction
