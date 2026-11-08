" Formatters turn kubectl output into the rows of a table.
"
" A formatter is a dict:
"   headers: the column headers,
"   fn: the function(data, kbuf) returning the rows,
"   empty: the status shown when there are no rows (optional),
"   editable: {header: function(kbuf, item, old, new)} of the columns that :w
"     applies, see kube#edits (optional),
"   metrics: the kubectl top kind of the rows, pods or nodes, adds CPU and
"     MEMORY columns to lists (optional).
" A row is a dict: row (the cells), item (the resource), highlights ({header:
" group} of cells, optional), diagnostics ([{message, severity}], optional,
" severity is error, warn or info).

function! s:get(dict, key, default) abort
  return kube#utils#get(a:dict, a:key, a:default)
endfunction

function! s:dig(dict, path, default) abort
  return kube#utils#dig(a:dict, a:path, a:default)
endfunction

function! s:age(item) abort
  return kube#utils#calculate_age(a:item.metadata.creationTimestamp)
endfunction

function! s:count(dict, key) abort
  return string(len(s:get(a:dict, a:key, {})))
endfunction

function! s:ready(item) abort
  return printf('%d/%d', s:dig(a:item, 'status.readyReplicas', 0), s:dig(a:item, 'status.replicas', 0))
endfunction

" The IP of the first load balancer ingress, as kubectl shows it.
function! s:load_balancer(item) abort
  let ingress = s:dig(a:item, 'status.loadBalancer.ingress', [])
  return empty(ingress) ? '<pending>' : s:get(ingress[0], 'ip', '<pending>')
endfunction

function! s:ports(ports, key) abort
  return map(copy(a:ports), 'printf("%d/%s", v:val[a:key], s:get(v:val, "protocol", "TCP"))')
endfunction

function! s:default(data, kbuf) abort
  return map(copy(a:data.items), '{"row": [s:get(v:val.metadata, "namespace", ""), v:val.metadata.name, s:age(v:val)], "item": v:val}')
endfunction

function! s:pods(data, kbuf) abort
  let rows = []
  for pod in a:data.items
    let pod_status = s:get(pod, 'status', {})
    let phase = s:get(pod_status, 'phase', '')
    let status = kube#status#pod(pod)
    let highlights = {'STATUS': kube#status#highlight(status)}

    let statuses = kube#utils#list(pod_status, 'containerStatuses')
    let ready_count = len(filter(copy(statuses), '!empty(s:get(v:val, "ready", 0))'))
    let container_count = len(pod.spec.containers)
    if status ==# 'Running' && ready_count < container_count
      let highlights.READY = 'KubePending'
    endif

    let restarts = 0
    for container in statuses
      let restarts += s:get(container, 'restartCount', 0)
    endfor
    if restarts > 0
      let highlights.RESTARTS = 'KubePending'
    endif

    if status ==# 'Terminating'
      let severity = 'info'
    elseif highlights.STATUS ==# 'KubeFailed'
      let severity = 'error'
    else
      let severity = get({'Pending': 'warn', 'Failed': 'error'}, phase, 'error')
    endif

    let diagnostics = []
    if index(['Completed', 'Succeeded'], status) < 0
      let conditions = s:get(pod_status, 'conditions', v:null)
      if type(conditions) == v:t_list
        for condition in conditions
          " A single condition is the reason the pod is not ready yet, e.g. it
          " cannot be scheduled
          if (len(conditions) == 1 || s:get(condition, 'type', '') ==# 'Ready') && s:get(condition, 'status', '') !=# 'True'
            let message = s:get(condition, 'message', s:get(condition, 'reason', ''))
            call add(diagnostics, {'message': 'The pod is not ready: ' . message, 'severity': severity})
          endif
        endfor
      elseif !empty(s:get(pod_status, 'message', ''))
        call add(diagnostics, {'message': pod_status.message, 'severity': severity})
      endif
    endif

    call add(rows, {
          \ 'row': [pod.metadata.namespace, pod.metadata.name, printf('%d/%d', ready_count, container_count),
          \   status, string(restarts), s:get(pod_status, 'podIP', ''), s:dig(pod, 'spec.nodeName', ''), s:age(pod)],
          \ 'highlights': highlights,
          \ 'item': pod,
          \ 'diagnostics': diagnostics,
          \ })
  endfor
  return rows
endfunction

function! s:container_rows(rows, containers, statuses, Type) abort
  let by_name = {}
  for container_status in a:statuses
    let by_name[container_status.name] = container_status
  endfor
  for container in a:containers
    let container_status = get(by_name, container.name, v:null)
    let [text, highlight] = kube#status#container(container_status)
    let restarts = s:get(container_status, 'restartCount', 0)
    let highlights = {'STATUS': highlight}
    if restarts > 0
      let highlights.RESTARTS = 'KubePending'
    endif
    call add(a:rows, {
          \ 'row': [container.name, a:Type(container), text, string(restarts), s:get(container, 'image', ''),
          \   join(s:ports(kube#utils#list(container, 'ports'), 'containerPort'), ', ')],
          \ 'highlights': highlights,
          \ 'item': container,
          \ })
  endfor
endfunction

" The containers of a pod, in the order they start.
function! s:containers(pod, kbuf) abort
  let pod_status = s:get(a:pod, 'status', {})
  let rows = []
  call s:container_rows(rows, kube#utils#list(a:pod.spec, 'initContainers'),
        \ kube#utils#list(pod_status, 'initContainerStatuses'),
        \ {container -> s:get(container, 'restartPolicy', '') ==# 'Always' ? 'sidecar' : 'init'})
  call s:container_rows(rows, kube#utils#list(a:pod.spec, 'containers'),
        \ kube#utils#list(pod_status, 'containerStatuses'), {container -> 'main'})
  return rows
endfunction

function! s:deployments(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name, s:ready(v:val),
        \ string(s:dig(v:val, "spec.replicas", 1)), string(s:dig(v:val, "status.updatedReplicas", 0)),
        \ string(s:dig(v:val, "status.availableReplicas", 0)), s:age(v:val)]}')
endfunction

function! s:statefulsets(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name, s:ready(v:val),
        \ string(s:dig(v:val, "spec.replicas", 1)), s:dig(v:val, "spec.serviceName", ""), s:age(v:val)]}')
endfunction

function! s:replicasets(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name,
        \ string(s:dig(v:val, "spec.replicas", 1)), string(s:dig(v:val, "status.currentReplicas", 0)), s:ready(v:val), s:age(v:val)]}')
endfunction

function! s:daemonsets(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name,
        \ string(s:dig(v:val, "status.desiredNumberScheduled", 0)), string(s:dig(v:val, "status.currentNumberScheduled", 0)),
        \ string(s:dig(v:val, "status.numberReady", 0)), string(s:dig(v:val, "status.numberAvailable", 0)), s:age(v:val)]}')
endfunction

function! s:cronjobs(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name,
        \ s:dig(v:val, "spec.schedule", ""), s:dig(v:val, "spec.suspend", v:false) is v:true ? "true" : "false",
        \ s:dig(v:val, "status.lastScheduleTime", "<none>"), s:age(v:val)]}')
endfunction

" The condition of {type} of a job that is true, {} if none.
function! s:condition(job, type) abort
  for condition in kube#utils#list(s:get(a:job, 'status', {}), 'conditions')
    if s:get(condition, 'type', '') ==# a:type && s:get(condition, 'status', '') ==# 'True'
      return condition
    endif
  endfor
  return {}
endfunction

" Like the STATUS of kubectl get jobs: [status, highlight].
function! s:job_status(job) abort
  if !empty(s:condition(a:job, 'Complete'))
    return ['Complete', 'KubeSucceeded']
  elseif !empty(s:condition(a:job, 'Failed'))
    return ['Failed', 'KubeFailed']
  elseif type(s:dig(a:job, 'metadata.deletionTimestamp', v:null)) == v:t_string
    return ['Terminating', 'KubePending']
  elseif !empty(s:condition(a:job, 'Suspended'))
    return ['Suspended', 'KubeUnknown']
  endif
  return ['Running', 'KubeRunning']
endfunction

" Like the COMPLETIONS of kubectl get jobs.
function! s:completions(job) abort
  let succeeded = s:dig(a:job, 'status.succeeded', 0)
  let completions = s:dig(a:job, 'spec.completions', v:null)
  if type(completions) == v:t_number
    return printf('%d/%d', succeeded, completions)
  endif
  let parallelism = s:dig(a:job, 'spec.parallelism', 1)
  if parallelism > 1
    return printf('%d/1 of %d', succeeded, parallelism)
  endif
  return printf('%d/1', succeeded)
endfunction

function! s:duration(job) abort
  let start = s:dig(a:job, 'status.startTime', v:null)
  if type(start) != v:t_string
    return ''
  endif
  let completion = s:dig(a:job, 'status.completionTime', v:null)
  let finished = type(completion) == v:t_string ? kube#utils#parse_time(completion) : localtime()
  return kube#utils#format_duration(finished - kube#utils#parse_time(start))
endfunction

function! s:jobs(data, kbuf) abort
  let rows = []
  for job in a:data.items
    let [status, highlight] = s:job_status(job)
    let row = {
          \ 'row': [job.metadata.namespace, job.metadata.name, status, s:completions(job), s:duration(job), s:age(job)],
          \ 'highlights': {'STATUS': highlight},
          \ 'item': job,
          \ }
    if status ==# 'Failed'
      let failed = s:condition(job, 'Failed')
      let row.diagnostics = [{'message': s:get(failed, 'message', s:get(failed, 'reason', 'The job failed')), 'severity': 'error'}]
    endif
    call add(rows, row)
  endfor
  return rows
endfunction

function! s:namespaces(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.name, s:dig(v:val, "status.phase", "Unknown"), s:age(v:val)]}')
endfunction

" Like the STATUS of kubectl get nodes: Ready, NotReady or Unknown, and
" whether it is cordoned.
function! s:node_status(node) abort
  let status = 'Unknown'
  for condition in kube#utils#list(s:get(a:node, 'status', {}), 'conditions')
    if s:get(condition, 'type', '') ==# 'Ready'
      let status = get({'True': 'Ready', 'False': 'NotReady'}, s:get(condition, 'status', ''), 'Unknown')
    endif
  endfor
  if s:dig(a:node, 'spec.unschedulable', v:false) is v:true
    let status .= ',SchedulingDisabled'
  endif
  return status
endfunction

function! s:nodes(data, kbuf) abort
  let rows = []
  for node in a:data.items
    let roles = []
    for label in keys(s:get(node.metadata, 'labels', {}))
      if label =~# '^node-role\.kubernetes\.io/'
        call add(roles, substitute(label, '^node-role\.kubernetes\.io/', '', ''))
      endif
    endfor
    let status = s:node_status(node)
    let ready = status =~# '^Ready'
    let row = {
          \ 'row': [node.metadata.name, status, join(sort(roles), ','), s:age(node), s:dig(node, 'status.nodeInfo.kubeletVersion', '')],
          \ 'highlights': {'STATUS': status ==# 'Ready' ? 'KubeRunning' : ready ? 'KubePending' : 'KubeFailed'},
          \ 'item': node,
          \ }
    if !ready
      let row.diagnostics = [{'message': 'The node is ' . status, 'severity': 'error'}]
    endif
    call add(rows, row)
  endfor
  return rows
endfunction

function! s:services(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name,
        \ s:dig(v:val, "spec.type", "ClusterIP"), s:dig(v:val, "spec.clusterIP", "<none>"), s:load_balancer(v:val),
        \ join(s:ports(kube#utils#list(v:val.spec, "ports"), "port"), ","), s:age(v:val)]}')
endfunction

function! s:ingresses(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.name, s:dig(v:val, "spec.ingressClassName", "<none>"),
        \ join(map(copy(kube#utils#list(v:val.spec, "rules")), "s:get(v:val, ''host'', ''*'')"), ","), s:load_balancer(v:val),
        \ join(s:ports(kube#utils#list(v:val.spec, "ports"), "port"), ","), s:age(v:val)]}')
endfunction

function! s:configmaps(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name, s:count(v:val, "data"), s:age(v:val)]}')
endfunction

function! s:secrets(data, kbuf) abort
  return map(copy(a:data.items), '{"item": v:val, "row": [v:val.metadata.namespace, v:val.metadata.name,
        \ s:get(v:val, "type", "Opaque"), s:count(v:val, "data"), s:age(v:val)]}')
endfunction

function! s:gateways(data, kbuf) abort
  let rows = []
  for item in a:data.items
    let hosts = []
    for server in kube#utils#list(item.spec, 'servers')
      call extend(hosts, kube#utils#list(server, 'hosts'))
    endfor
    call add(rows, {'item': item, 'row': [item.metadata.namespace, item.metadata.name, join(uniq(sort(hosts)), ','), s:age(item)]})
  endfor
  return rows
endfunction

function! s:last_seen(event) abort
  let time = s:get(a:event, 'lastTimestamp', s:get(a:event, 'eventTime', s:dig(a:event, 'metadata.creationTimestamp', '')))
  return type(time) == v:t_string ? time : ''
endfunction

function! s:by_last_seen(a, b) abort
  let [a, b] = [s:last_seen(a:a)[0:18], s:last_seen(a:b)[0:18]]
  return a ># b ? -1 : a <# b ? 1 : 0
endfunction

function! s:events(data, kbuf) abort
  let rows = []
  " Most recent first, ISO timestamps sort lexicographically
  for event in sort(copy(a:data.items), function('s:by_last_seen'))
    let object = s:get(event, 'involvedObject', {})
    let message = substitute(s:get(event, 'message', ''), '\s*\n\s*', ' ', 'g')
    let warning = s:get(event, 'type', '') ==# 'Warning'
    let seen = s:last_seen(event)
    let row = {
          \ 'row': [s:dig(event, 'metadata.namespace', ''), empty(seen) ? '' : kube#utils#calculate_age(seen),
          \   s:get(event, 'type', ''), s:get(event, 'reason', ''),
          \   printf('%s/%s', tolower(s:get(object, 'kind', '')), s:get(object, 'name', '')), message],
          \ 'item': event,
          \ }
    if warning
      let row.highlights = {'TYPE': 'KubePending'}
      let row.diagnostics = [{'message': message, 'severity': 'warn'}]
    endif
    call add(rows, row)
  endfor
  return rows
endfunction

" The resource types of kubectl api-resources, rows open the list of their type.
function! s:api_resources(resources, kbuf) abort
  let rows = []
  for resource in a:resources
    let group = matchstr(resource.apiversion, '^\zs.\+\ze/[^/]\+$')
    call add(rows, {
          \ 'row': [resource.name, resource.shortnames, resource.apiversion, resource.namespaced, resource.kind],
          \ 'item': {
          \   'kind': 'APIResource',
          \   'name': empty(group) ? resource.name : resource.name . '.' . group,
          \   'namespaced': resource.namespaced ==# 'true',
          \   'object_kind': resource.kind,
          \ },
          \ })
  endfor
  return rows
endfunction

function! s:by_local_port(a, b) abort
  return a:a.item.local_port - a:b.item.local_port
endfunction

" The port forwards of the resource {parent} in the buffer's context.
function! s:portforward(parent, kbuf) abort
  let namespace = a:parent.metadata.namespace
  let name = a:parent.metadata.name
  let key = kube#utils#portforward_key(a:kbuf.context, namespace, kube#utils#resource_type(a:parent), name)
  let rows = []
  for [local_port, forward] in items(get(kube#portforward#all(), key, {}))
    call add(rows, {
          \ 'row': [namespace, a:parent.kind . '/' . name, local_port, string(forward.container_port), 'http://localhost:' . local_port],
          \ 'item': {'id': key, 'portforward': forward, 'local_port': str2nr(local_port)},
          \ })
  endfor
  return sort(rows, function('s:by_local_port'))
endfunction

" All port forwards, across resources and contexts.
function! s:portforwards(data, kbuf) abort
  let rows = []
  for [key, forwards] in items(kube#portforward#all())
    for [local_port, forward] in items(forwards)
      call add(rows, {
            \ 'row': [forward.context, forward.namespace, forward.resource_type . '/' . forward.name, local_port,
            \   string(forward.container_port), 'http://localhost:' . local_port],
            \ 'item': {'id': key, 'portforward': forward, 'local_port': str2nr(local_port)},
            \ })
    endfor
  endfor
  return sort(rows, function('s:by_local_port'))
endfunction

let s:formatters = {
      \ 'default': {'headers': ['NAMESPACE', 'NAME', 'AGE'], 'fn': function('s:default')},
      \ 'pods': {'headers': ['NAMESPACE', 'NAME', 'READY', 'STATUS', 'RESTARTS', 'IP', 'NODE', 'AGE'], 'fn': function('s:pods'), 'metrics': 'pods'},
      \ 'deployments': {'headers': ['NAMESPACE', 'NAME', 'READY', 'DESIRED', 'UP-TO-DATE', 'AVAILABLE', 'AGE'], 'fn': function('s:deployments'),
      \   'editable': {'DESIRED': function('kube#edits#replicas')}},
      \ 'nodes': {'headers': ['NAME', 'STATUS', 'ROLES', 'AGE', 'VERSION'], 'fn': function('s:nodes'), 'metrics': 'nodes'},
      \ 'namespaces': {'headers': ['NAME', 'STATUS', 'AGE'], 'fn': function('s:namespaces')},
      \ 'services': {'headers': ['NAMESPACE', 'NAME', 'TYPE', 'CLUSTER-IP', 'EXTERNAL-IP', 'PORT(S)', 'AGE'], 'fn': function('s:services')},
      \ 'ingresses': {'headers': ['NAME', 'CLASS', 'HOSTS', 'ADDRESS', 'PORTS', 'AGE'], 'fn': function('s:ingresses')},
      \ 'configmaps': {'headers': ['NAMESPACE', 'NAME', 'DATA', 'AGE'], 'fn': function('s:configmaps')},
      \ 'secrets': {'headers': ['NAMESPACE', 'NAME', 'TYPE', 'DATA', 'AGE'], 'fn': function('s:secrets')},
      \ 'containers': {'headers': ['NAME', 'TYPE', 'STATUS', 'RESTARTS', 'IMAGE', 'PORTS'], 'fn': function('s:containers'),
      \   'editable': {'IMAGE': function('kube#edits#image')}},
      \ 'portforward': {'headers': ['NAMESPACE', 'RESOURCE', 'LOCAL_PORT', 'CONTAINER_PORT', 'URL'], 'fn': function('s:portforward')},
      \ 'portforwards': {'headers': ['CONTEXT', 'NAMESPACE', 'RESOURCE', 'LOCAL_PORT', 'CONTAINER_PORT', 'URL'], 'fn': function('s:portforwards')},
      \ 'events': {'headers': ['NAMESPACE', 'LAST SEEN', 'TYPE', 'REASON', 'OBJECT', 'MESSAGE'], 'fn': function('s:events'),
      \   'empty': 'No events: Kubernetes keeps events for 1 hour by default'},
      \ 'api-resources': {'headers': ['NAME', 'SHORTNAMES', 'APIVERSION', 'NAMESPACED', 'KIND'], 'fn': function('s:api_resources')},
      \ 'helm-releases': {'headers': ['NAMESPACE', 'NAME', 'REVISION', 'STATUS', 'CHART', 'APP VERSION', 'UPDATED'],
      \   'fn': function('helm#format#releases'), 'empty': 'No releases found'},
      \ 'helm-history': {'headers': ['REVISION', 'UPDATED', 'STATUS', 'CHART', 'APP VERSION', 'DESCRIPTION'],
      \   'fn': function('helm#format#history'), 'empty': 'No revisions found'},
      \ 'cronjobs': {'headers': ['NAMESPACE', 'NAME', 'SCHEDULE', 'SUSPENDED', 'LAST SCHEDULE', 'AGE'], 'fn': function('s:cronjobs'),
      \   'editable': {'SUSPENDED': function('kube#edits#suspend')}},
      \ 'jobs': {'headers': ['NAMESPACE', 'NAME', 'STATUS', 'COMPLETIONS', 'DURATION', 'AGE'], 'fn': function('s:jobs')},
      \ 'daemonsets': {'headers': ['NAMESPACE', 'NAME', 'DESIRED', 'CURRENT', 'READY', 'AVAILABLE', 'AGE'], 'fn': function('s:daemonsets')},
      \ 'statefulsets': {'headers': ['NAMESPACE', 'NAME', 'READY', 'DESIRED', 'SERVICE', 'AGE'], 'fn': function('s:statefulsets'),
      \   'editable': {'DESIRED': function('kube#edits#replicas')}},
      \ 'replicasets': {'headers': ['NAMESPACE', 'NAME', 'DESIRED', 'CURRENT', 'READY', 'AGE'], 'fn': function('s:replicasets'),
      \   'editable': {'DESIRED': function('kube#edits#replicas')}},
      \ 'gateways': {'headers': ['NAMESPACE', 'NAME', 'HOSTS', 'AGE'], 'fn': function('s:gateways')},
      \ }

" Aliases include the group-qualified singular of kube#utils#resource_type(),
" used by parent buffers
let s:aliases = {}
for [s:name, s:names] in items({
      \ 'pods': ['pod', 'po'],
      \ 'deployments': ['deployment', 'deploy', 'deployments.apps', 'deployment.apps'],
      \ 'nodes': ['node', 'no'],
      \ 'namespaces': ['namespace', 'ns'],
      \ 'services': ['service', 'svc'],
      \ 'ingresses': ['ingress', 'ing', 'ingresses.networking.k8s.io', 'ingress.networking.k8s.io'],
      \ 'configmaps': ['configmap', 'cm'],
      \ 'secrets': ['secret'],
      \ 'events': ['event', 'ev'],
      \ 'cronjobs': ['cronjob', 'cronjobs.batch', 'cronjob.batch'],
      \ 'jobs': ['job', 'jobs.batch', 'job.batch'],
      \ 'daemonsets': ['daemonset', 'ds', 'daemonsets.apps', 'daemonset.apps'],
      \ 'statefulsets': ['statefulset', 'sts', 'statefulsets.apps', 'statefulset.apps'],
      \ 'replicasets': ['replicaset', 'rs', 'replicasets.apps', 'replicaset.apps'],
      \ 'gateways': ['gateway', 'gw', 'gateways.networking.istio.io', 'gateway.networking.istio.io'],
      \ })
  for s:alias in s:names
    let s:aliases[s:alias] = s:name
  endfor
endfor
for s:name in keys(s:formatters)
  let s:aliases[s:name] = s:name
endfor
unlet s:name s:names s:alias

" The formatter of {kind}, the default one for other kinds.
function! kube#format#get(kind) abort
  return s:formatters[get(s:aliases, a:kind, 'default')]
endfunction
