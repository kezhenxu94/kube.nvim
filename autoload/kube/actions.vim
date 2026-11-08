" Actions on the resource of the row under the cursor, by its kind. They get
" the buffer the resource was selected from, which provides the context and,
" for rows that are not resources like containers, the parent resource.

" Open a buffer for {resource}, in the context of the buffer it was selected
" from.
function! kube#actions#open_resource(kbuf, resource, subresource, params) abort
  call kube#utils#open({
        \ 'context': a:kbuf.context,
        \ 'namespace': kube#utils#get(a:resource.metadata, 'namespace', ''),
        \ 'kind': kube#utils#resource_type(a:resource),
        \ 'name': a:resource.metadata.name,
        \ 'subresource': a:subresource,
        \ 'params': a:params,
        \ })
endfunction

" Open the pods matching the labels {selector}.
function! s:open_pods(kbuf, namespace, selector) abort
  let labels = sort(map(items(type(a:selector) == v:t_dict ? a:selector : {}), 'v:val[0] . "=" . v:val[1]'))
  call kube#utils#open({
        \ 'context': a:kbuf.context,
        \ 'namespace': a:namespace,
        \ 'kind': 'pods',
        \ 'params': empty(labels) ? {} : {'selector': join(labels, ',')},
        \ })
endfunction

function! s:selected_pods(kbuf, resource) abort
  call s:open_pods(a:kbuf, a:resource.metadata.namespace, kube#utils#dig(a:resource, 'spec.selector.matchLabels', {}))
endfunction

function! s:logs(kbuf, resource, follow) abort
  call kube#actions#open_resource(a:kbuf, a:resource, 'logs', a:follow ? {'follow': v:true} : {})
endfunction

function! s:show_portforwards(kbuf, resource) abort
  call kube#actions#open_resource(a:kbuf, a:resource, 'portforward', {})
endfunction

function! s:yaml(kbuf, resource) abort
  call kube#actions#open_resource(a:kbuf, a:resource, '', {'output': 'yaml'})
endfunction

function! s:describe(kbuf, resource) abort
  call kube#actions#open_resource(a:kbuf, a:resource, '', {})
endfunction

function! s:no_logs(kbuf, resource, follow) abort
  call resource#notify(printf('%s resources do not support logs', a:resource.kind), 'warn')
endfunction

" The containers of a pod template.
function! s:template_containers(resource) abort
  return kube#utils#dig(a:resource, 'spec.template.spec.containers', [])
endfunction

function! s:set_image(kbuf, resource, containers) abort
  let containers = map(copy(a:containers), '{"name": v:val.name, "image": kube#utils#get(v:val, "image", "")}')
  call kube#actions#prompt_set_image(a:kbuf.context, containers, kube#utils#resource_type(a:resource),
        \ a:resource.metadata.name, a:resource.metadata.namespace, {changed -> changed ? resource#load(a:kbuf) : 0})
endfunction

" The ports of {containers}: [{container, port, protocol}].
function! s:ports(containers) abort
  let ports = []
  for container in a:containers
    for port in kube#utils#list(container, 'ports')
      call add(ports, {'container': container.name, 'port': port.containerPort, 'protocol': kube#utils#get(port, 'protocol', 'TCP')})
    endfor
  endfor
  return ports
endfunction

function! s:forward_port(kbuf, resource, containers) abort
  call kube#portforward#prompt(a:kbuf.context, s:ports(a:containers), kube#utils#resource_type(a:resource),
        \ a:resource.metadata.name, a:resource.metadata.namespace)
endfunction

function! s:exec(kbuf, resource, containers) abort
  call kube#exec#prompt_exec(a:kbuf.context, a:containers, kube#utils#resource_type(a:resource),
        \ a:resource.metadata.name, a:resource.metadata.namespace)
endfunction

" Pods

function! s:pod_containers(kbuf, pod) abort
  call kube#actions#open_resource(a:kbuf, a:pod, 'containers', {})
endfunction

function! s:pod_set_image(kbuf, pod) abort
  call s:set_image(a:kbuf, a:pod, a:pod.spec.containers)
endfunction

function! s:pod_forward_port(kbuf, pod) abort
  call s:forward_port(a:kbuf, a:pod, a:pod.spec.containers)
endfunction

function! s:pod_exec(kbuf, pod) abort
  call s:exec(a:kbuf, a:pod, a:pod.spec.containers)
endfunction

" Workloads

function! s:template_set_image(kbuf, resource) abort
  call s:set_image(a:kbuf, a:resource, s:template_containers(a:resource))
endfunction

function! s:template_forward_port(kbuf, resource) abort
  call s:forward_port(a:kbuf, a:resource, s:template_containers(a:resource))
endfunction

function! s:template_exec(kbuf, resource) abort
  call s:exec(a:kbuf, a:resource, s:template_containers(a:resource))
endfunction

function! s:cronjob_set_image(kbuf, cronjob) abort
  call s:set_image(a:kbuf, a:cronjob, kube#utils#dig(a:cronjob, 'spec.jobTemplate.spec.template.spec.containers', []))
endfunction

" Services

function! s:service_pods(kbuf, service) abort
  call s:open_pods(a:kbuf, a:service.metadata.namespace, kube#utils#dig(a:service, 'spec.selector', {}))
endfunction

function! s:service_forward_port(kbuf, service) abort
  let ports = map(copy(kube#utils#list(a:service.spec, 'ports')),
        \ '{"name": kube#utils#get(v:val, "name", ""), "ports": [{"containerPort": v:val.port, "protocol": kube#utils#get(v:val, "protocol", "TCP")}]}')
  call s:forward_port(a:kbuf, a:service, ports)
endfunction

function! s:service_exec(kbuf, service) abort
  call s:exec(a:kbuf, a:service, [])
endfunction

function! s:secret_data(kbuf, secret) abort
  call kube#actions#open_resource(a:kbuf, a:secret, 'data', {})
endfunction

" Containers: rows of the kube://.../pod/{name}/containers buffer, the buffer
" identifies the parent pod

function! s:container_exec(kbuf, container) abort
  call kube#exec#prompt_exec(a:kbuf.context, [a:container], a:kbuf.resource_kind, a:kbuf.resource_name, a:kbuf.namespace)
endfunction

function! kube#actions#container_logs(kbuf, container, params) abort
  call kube#utils#open({
        \ 'context': a:kbuf.context,
        \ 'namespace': a:kbuf.namespace,
        \ 'kind': a:kbuf.resource_kind,
        \ 'name': a:kbuf.resource_name,
        \ 'subresource': 'logs',
        \ 'params': extend({'container': a:container.name}, a:params),
        \ })
endfunction

function! s:container_show_logs(kbuf, container, follow) abort
  call kube#actions#container_logs(a:kbuf, a:container, a:follow ? {'follow': v:true} : {})
endfunction

function! s:container_forward_port(kbuf, container) abort
  let ports = map(copy(kube#utils#list(a:container, 'ports')),
        \ '{"container": a:container.name, "port": v:val.containerPort, "protocol": kube#utils#get(v:val, "protocol", "TCP")}')
  " Normalized from the loaded pod (e.g. pods -> pod) to match the key of the
  " port forwards buffer
  let kind = type(a:kbuf.data) == v:t_dict ? kube#utils#resource_type(a:kbuf.data) : a:kbuf.resource_kind
  call kube#portforward#prompt(a:kbuf.context, ports, kind, a:kbuf.resource_name, a:kbuf.namespace)
endfunction

" Resource types of kube://

function! s:apiresource_list(kbuf, type) abort
  call resource#open(kube#navigation#api_resource_target(a:kbuf, a:type))
endfunction

" Helm releases and their revisions

function! kube#actions#open_release(kbuf, release, subresource, params) abort
  call kube#utils#open({
        \ 'context': a:kbuf.context,
        \ 'namespace': a:release.namespace,
        \ 'kind': 'helm-releases',
        \ 'name': a:release.name,
        \ 'subresource': a:subresource,
        \ 'params': a:params,
        \ })
endfunction

function! s:release_manifest(kbuf, release) abort
  call kube#actions#open_release(a:kbuf, a:release, 'manifest', {})
endfunction

function! s:release_values(kbuf, release) abort
  call kube#actions#open_release(a:kbuf, a:release, 'values', {})
endfunction

function! s:release_status(kbuf, release) abort
  call kube#actions#open_release(a:kbuf, a:release, '', {})
endfunction

function! s:revision_manifest(kbuf, revision) abort
  call kube#actions#open_release(a:kbuf, {'name': a:revision.release, 'namespace': a:revision.namespace}, 'manifest',
        \ {'revision': a:revision.revision})
endfunction

let s:pod = {
      \ 'drill_down_resource': function('s:pod_containers'),
      \ 'show_logs': function('s:logs'),
      \ 'port_forward': function('s:show_portforwards'),
      \ 'forward_port': function('s:pod_forward_port'),
      \ 'set_image': function('s:pod_set_image'),
      \ 'exec': function('s:pod_exec'),
      \ }
let s:container = {
      \ 'drill_down_resource': function('s:container_exec'),
      \ 'show_logs': function('s:container_show_logs'),
      \ 'forward_port': function('s:container_forward_port'),
      \ 'exec': function('s:container_exec'),
      \ }
let s:actions = {
      \ 'pod': s:pod,
      \ 'container': s:container,
      \ 'containers': s:container,
      \ 'deployment': {
      \   'drill_down_resource': function('s:selected_pods'),
      \   'show_logs': function('s:logs'),
      \   'port_forward': function('s:show_portforwards'),
      \   'forward_port': function('s:template_forward_port'),
      \   'set_image': function('s:template_set_image'),
      \   'exec': function('s:template_exec'),
      \ },
      \ 'cronjob': {'set_image': function('s:cronjob_set_image')},
      \ 'job': {'drill_down_resource': function('s:selected_pods'), 'show_logs': function('s:logs')},
      \ 'daemonset': {'set_image': function('s:template_set_image')},
      \ 'statefulset': {'drill_down_resource': function('s:selected_pods'), 'set_image': function('s:template_set_image')},
      \ 'replicaset': {'drill_down_resource': function('s:selected_pods'), 'set_image': function('s:template_set_image')},
      \ 'service': {
      \   'drill_down_resource': function('s:service_pods'),
      \   'forward_port': function('s:service_forward_port'),
      \   'exec': function('s:service_exec'),
      \ },
      \ 'secret': {'drill_down_resource': function('s:secret_data')},
      \ 'apiresource': {'drill_down_resource': function('s:apiresource_list')},
      \ 'helmrelease': {
      \   'drill_down_resource': function('s:release_manifest'),
      \   'show_yaml': function('s:release_values'),
      \   'describe': function('s:release_status'),
      \ },
      \ 'helmrevision': {'drill_down_resource': function('s:revision_manifest')},
      \ }

" The defaults need a Kubernetes object
let s:default = {
      \ 'drill_down_resource': function('s:yaml'),
      \ 'show_yaml': function('s:yaml'),
      \ 'describe': function('s:describe'),
      \ 'show_logs': function('s:no_logs'),
      \ }
" Rows that are not objects. Helm releases are not objects either: helmrelease
" may be another type, e.g. Flux's HelmRelease
let s:NON_OBJECT_ROWS = ['container', 'containers', 'portforward', 'apiresource', 'helmrelease', 'helmrevision']

" The action {name} for rows of {kind}, v:null if none.
function! kube#actions#get(kind, name) abort
  let actions = get(s:actions, a:kind, {})
  if has_key(actions, a:name)
    return actions[a:name]
  endif
  if index(s:NON_OBJECT_ROWS, a:kind) < 0
    return get(s:default, a:name, v:null)
  endif
  return v:null
endfunction

" Run the action {name} on the resource under the cursor. Rows without a kind
" (e.g. containers) are dispatched by the buffer's subresource kind.
function! kube#actions#run(kbuf, name, ...) abort
  let resource = resource#item(a:kbuf)
  if type(resource) != v:t_dict
    return
  endif
  let kind = get(resource, 'kind', a:kbuf.subresource_kind)
  if empty(kind)
    return
  endif
  let Action = kube#actions#get(tolower(kind), a:name)
  if Action is v:null
    call resource#notify(printf('%s is not supported for %s', a:name, kind), 'warn')
    return
  endif
  call call(Action, [a:kbuf, resource] + a:000)
endfunction

" Prompt for the container of {containers} ([{name, image}]) and its new image.
function! kube#actions#prompt_set_image(context, containers, kind, name, namespace, Callback) abort
  if empty(a:containers)
    call resource#notify('No containers available', 'warn')
    return
  endif
  call resource#select(map(copy(a:containers), 'v:val.name . ": " . v:val.image'), {'prompt': 'Select container to update:'},
        \ function('s:on_container', [a:context, a:containers, a:kind, a:name, a:namespace, a:Callback]))
endfunction

function! s:on_container(context, containers, kind, name, namespace, Callback, choice, index) abort
  if a:choice is v:null
    return
  endif
  let container = a:containers[a:index - 1]
  call resource#input({'prompt': 'New image: ', 'default': container.image},
        \ function('s:on_image', [a:context, container, a:kind, a:name, a:namespace, a:Callback]))
endfunction

function! s:on_image(context, container, kind, name, namespace, Callback, image) abort
  if a:image is v:null
    call a:Callback(0)
    return
  endif
  call kube#kubectl#set_image(a:context, a:kind, a:name, a:namespace, a:container.name, a:image,
        \ function('s:image_set', [a:container, a:image, a:Callback]), {err -> resource#notify(err, 'error')})
endfunction

function! s:image_set(container, image, Callback, result) abort
  if a:result isnot v:null
    call resource#notify(printf("Successfully updated image for container '%s' to '%s'", a:container.name, a:image))
  endif
  call a:Callback(a:result isnot v:null)
endfunction
