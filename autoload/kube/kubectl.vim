" kubectl, run asynchronously unless named *_sync.
"
" {context} is the context to run against, v:null or '' for the kubeconfig
" current-context. Callbacks get stdout on success, v:null on failure, error
" callbacks ({OnError}, optional: v:null) the stderr of failures.

" The context switched to with :Kube context, kept across sessions
let s:context = v:null

function! s:state_file() abort
  return kube#compat#state_file('kube_state.json')
endfunction

function! s:load_state() abort
  let file = s:state_file()
  if !filereadable(file)
    return
  endif
  try
    let state = json_decode(join(readfile(file), "\n"))
  catch
    return
  endtry
  if type(state) == v:t_dict && type(get(state, 'context', v:null)) == v:t_string
    let s:context = state.context
  endif
endfunction

call s:load_state()

" Upper bound of synchronous calls (completion), on top of the request timeout
let s:SYNC_TIMEOUT_MS = 10000

function! s:with_context(context, args) abort
  return (empty(a:context) ? ['kubectl'] : ['kubectl', '--context', a:context]) + a:args
endfunction

function! s:namespace_args(namespace) abort
  return empty(a:namespace) || tolower(a:namespace) ==# 'all' ? [] : ['-n', a:namespace]
endfunction

function! s:ref(resource_type, name) abort
  return a:resource_type . '/' . a:name
endfunction

" Run kubectl. {opts}: stream, for long-running commands without request
" timeout (port-forward, drain); ok_codes, exit codes that count as success
" ([0] by default); full, to call {Callback}(data, code, stderr).
function! s:kubectl(context, args, Callback, OnError, ...) abort
  let opts = get(a:, 1, {})
  let args = copy(a:args)
  if !get(opts, 'stream', 0)
    " Fail instead of hanging when the API server is unreachable
    call insert(args, '--request-timeout=' . kube#config#get('request_timeout'))
  endif
  return kube#compat#run(s:with_context(a:context, args),
        \ {'on_exit': function('s:on_exit', [get(opts, 'ok_codes', [0]), get(opts, 'full', 0), a:Callback, a:OnError])})
endfunction

function! s:on_exit(ok_codes, full, Callback, OnError, code, stdout, stderr) abort
  let success = index(a:ok_codes, a:code) >= 0
  if !success && type(a:OnError) == v:t_func
    call a:OnError(trim(a:stderr))
  endif
  if type(a:Callback) == v:t_func
    let data = success ? a:stdout : v:null
    if a:full
      call a:Callback(data, a:code, a:stderr)
    else
      call a:Callback(data)
    endif
  endif
endfunction

" Run kubectl synchronously, for completion: bounded so that an unreachable
" cluster cannot freeze the editor. Returns the lines of stdout, [] on failure.
function! s:kubectl_sync(context, args) abort
  let cmd = s:with_context(a:context, ['--request-timeout=' . kube#config#get('request_timeout')] + a:args)
  let [code, stdout] = kube#compat#system(cmd, s:SYNC_TIMEOUT_MS)
  return code == 0 ? split(stdout, "\n") : []
endfunction

" List {kind}, or get the resource {name}, as JSON. {namespace} 'all' for all
" namespaces, {params} extra --key=value flags.
function! kube#kubectl#get(context, kind, name, namespace, params, Callback, OnError) abort
  let args = ['get', a:kind, '-o', 'json']
  if !empty(a:name)
    call add(args, a:name)
  endif
  if !empty(a:namespace) && tolower(a:namespace) ==# 'all'
    call add(args, '--all-namespaces')
  else
    call extend(args, s:namespace_args(a:namespace))
  endif
  for key in sort(keys(a:params))
    call add(args, printf('--%s=%s', key, kube#utils#to_string(a:params[key])))
  endfor
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

function! kube#kubectl#get_resource_yaml(context, kind, name, namespace, Callback, OnError) abort
  let args = ['get', tolower(a:kind), a:name, '-o', 'yaml'] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" Logs, {opts}: container, follow, previous, all_containers, since, tail
" (g:kube_logs_tail by default). {Callback} gets complete lines, newline
" separated, of stdout and stderr: the errors are shown in place of the logs.
function! kube#kubectl#logs(context, kind, name, namespace, opts, Callback) abort
  let args = ['logs', s:ref(a:kind, a:name)]
  if !empty(get(a:opts, 'container', ''))
    call extend(args, ['-c', a:opts.container])
  endif
  call extend(args, s:namespace_args(a:namespace))
  call add(args, '--tail=' . get(a:opts, 'tail', kube#config#get('logs_tail')))
  if get(a:opts, 'previous', 0)
    call add(args, '--previous')
  endif
  if get(a:opts, 'all_containers', 0)
    call add(args, '--all-containers')
  endif
  if !empty(get(a:opts, 'since', ''))
    call add(args, '--since=' . a:opts.since)
  endif

  if !get(a:opts, 'follow', 0)
    return s:kubectl(a:context, args, function('s:logs_done', [a:Callback]), a:Callback)
  endif

  call add(args, '-f')
  " Emit only complete lines, as output arrives in arbitrary chunks
  let pending = {'stdout': '', 'stderr': '', 'callback': a:Callback}
  return kube#compat#run(s:with_context(a:context, args), {
        \ 'on_stdout': function('s:line_chunk', [pending, 'stdout']),
        \ 'on_stderr': function('s:line_chunk', [pending, 'stderr']),
        \ 'on_exit': function('s:line_flush', [pending]),
        \ })
endfunction

function! s:logs_done(Callback, data) abort
  if a:data isnot v:null
    call a:Callback(substitute(a:data, '\n$', '', ''))
  endif
endfunction

function! s:line_chunk(pending, stream, chunk) abort
  let a:pending[a:stream] .= a:chunk
  let last_newline = strridx(a:pending[a:stream], "\n")
  if last_newline >= 0
    call a:pending.callback(strpart(a:pending[a:stream], 0, last_newline))
    let a:pending[a:stream] = strpart(a:pending[a:stream], last_newline + 1)
  endif
endfunction

function! s:line_flush(pending, code, stdout, stderr) abort
  for stream in ['stdout', 'stderr']
    if a:pending[stream] !=# ''
      call a:pending.callback(a:pending[stream])
      let a:pending[stream] = ''
    endif
  endfor
endfunction

" Forward {local_port} to {port}, {Callback} is called once it exits.
function! kube#kubectl#forward_port(context, kind, name, namespace, port, local_port, Callback, OnError) abort
  let args = ['port-forward', s:ref(a:kind, a:name), printf('%d:%d', a:local_port, a:port)] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError, {'stream': 1})
endfunction

" The documentation of a resource type, e.g. deployments.apps.
function! kube#kubectl#explain(context, resource_type, Callback, OnError) abort
  return s:kubectl(a:context, ['explain', a:resource_type], a:Callback, a:OnError)
endfunction

function! kube#kubectl#describe(context, kind, name, namespace, Callback, OnError) abort
  return s:kubectl(a:context, ['describe', a:kind, a:name] + s:namespace_args(a:namespace), a:Callback, a:OnError)
endfunction

function! kube#kubectl#delete(context, kind, name, namespace, Callback, OnError) abort
  return s:kubectl(a:context, ['delete', a:kind, a:name] + s:namespace_args(a:namespace), a:Callback, a:OnError)
endfunction

" The context switched to with :Kube context, v:null if none.
function! kube#kubectl#context() abort
  return s:context
endfunction

function! kube#kubectl#set_context(context) abort
  let s:context = a:context
endfunction

" The context switched to with :Kube context, or the kubeconfig
" current-context, '' if none.
function! kube#kubectl#get_current_context() abort
  if type(s:context) == v:t_string
    return s:context
  endif
  return get(s:kubectl_sync(v:null, ['config', 'current-context']), 0, '')
endfunction

function! kube#kubectl#get_config(Callback) abort
  return s:kubectl(v:null, ['config', 'view', '-o', 'json'], a:Callback, v:null)
endfunction

" Switch the context of kube.nvim, the kubeconfig is not changed.
function! kube#kubectl#use_context(name, Callback) abort
  let s:context = a:name
  let file = s:state_file()
  call mkdir(fnamemodify(file, ':h'), 'p')
  call writefile([json_encode({'context': s:context})], file)
  call a:Callback(v:true)
endfunction

" The kubectl api-resources table, it has no JSON output. {Callback}(data,
" code, stderr) gets a partial list with code 1 when API groups fail.
function! kube#kubectl#api_resources(context, Callback, OnError) abort
  return s:kubectl(a:context, ['api-resources'], a:Callback, a:OnError, {'ok_codes': [0, 1], 'full': 1})
endfunction

let s:api_resources_cache = {}

" The names of the resource types, cached per context.
function! kube#kubectl#api_resources_sync() abort
  let key = type(s:context) == v:t_string ? s:context : ''
  if !has_key(s:api_resources_cache, key)
    let resources = s:kubectl_sync(s:context, ['api-resources', '--output=name'])
    if empty(resources)
      return resources
    endif
    let s:api_resources_cache[key] = resources
  endif
  return s:api_resources_cache[key]
endfunction

function! kube#kubectl#context_names_sync() abort
  return s:kubectl_sync(v:null, ['config', 'get-contexts', '--output=name'])
endfunction

" Apply the manifest {file}, in {namespace} unless v:null.
function! kube#kubectl#apply(context, namespace, file, Callback, OnError) abort
  return s:kubectl(a:context, s:namespace_args(a:namespace) + ['apply', '-f', a:file], a:Callback, a:OnError)
endfunction

" Diff the manifest {file} against the live objects: {Callback} gets the diff,
" '' when there are no differences.
function! kube#kubectl#diff(context, namespace, file, Callback, OnError) abort
  " kubectl diff exits with 1 when there are differences
  return s:kubectl(a:context, s:namespace_args(a:namespace) + ['diff', '-f', a:file], a:Callback, a:OnError, {'ok_codes': [0, 1]})
endfunction

function! kube#kubectl#set_image(context, kind, name, namespace, container, image, Callback, OnError) abort
  let args = ['set', 'image', s:ref(a:kind, a:name), a:container . '=' . a:image] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

function! kube#kubectl#scale(context, kind, name, namespace, replicas, Callback, OnError) abort
  let args = ['scale', s:ref(a:kind, a:name), '--replicas=' . a:replicas] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" {verb}: restart, undo or history.
function! kube#kubectl#rollout(context, verb, kind, name, namespace, Callback, OnError) abort
  let args = ['rollout', a:verb, s:ref(a:kind, a:name)] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" {verb}: cordon, uncordon or drain the node {name}.
function! kube#kubectl#node(context, verb, name, Callback, OnError) abort
  let args = [a:verb, a:name]
  if a:verb ==# 'drain'
    call extend(args, ['--ignore-daemonsets', '--delete-emptydir-data'])
  endif
  " Draining waits for pods to be evicted, which can take longer than a request
  return s:kubectl(a:context, args, a:Callback, a:OnError, {'stream': a:verb ==# 'drain'})
endfunction

" Patch with the JSON merge patch {patch}, a dict.
function! kube#kubectl#patch(context, kind, name, namespace, patch, Callback, OnError) abort
  let args = ['patch', a:kind, a:name, '--type=merge', '-p', json_encode(a:patch)] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" The command of an interactive kubectl exec session.
function! kube#kubectl#exec_cmd(context, kind, name, namespace, container) abort
  let args = ['exec', '-it', s:ref(tolower(a:kind), a:name)] + s:namespace_args(a:namespace)
  if !empty(a:container)
    call extend(args, ['-c', a:container])
  endif
  call extend(args, ['--', 'sh', '-c', 'command -v bash >/dev/null && exec bash || exec sh'])
  return s:with_context(a:context, args)
endfunction

" The command of an interactive kubectl debug session in an ephemeral
" container of the pod {name}, sharing the process namespace of {target}.
function! kube#kubectl#debug_cmd(context, name, namespace, image, target) abort
  let args = ['debug', '-it', s:ref('pod', a:name), '--image=' . a:image] + s:namespace_args(a:namespace)
  if !empty(a:target)
    call add(args, '--target=' . a:target)
  endif
  return s:with_context(a:context, args + ['--', 'sh'])
endfunction

" Create the job {job} from the cron job {cronjob}, to run it now.
function! kube#kubectl#create_job(context, cronjob, namespace, job, Callback, OnError) abort
  let args = ['create', 'job', a:job, '--from=' . s:ref('cronjob', a:cronjob)] + s:namespace_args(a:namespace)
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" Resource usage from the metrics API (kubectl top) of {kind}, pods or nodes.
function! kube#kubectl#top(context, kind, namespace, selector, Callback, OnError) abort
  let args = ['top', a:kind, '--no-headers']
  if a:kind ==# 'pods'
    if !empty(a:namespace) && tolower(a:namespace) ==# 'all'
      call add(args, '--all-namespaces')
    else
      call extend(args, s:namespace_args(a:namespace))
    endif
    if !empty(a:selector)
      call add(args, '--selector=' . a:selector)
    endif
  endif
  return s:kubectl(a:context, args, a:Callback, a:OnError)
endfunction

" The names of the resources of {kind}, in the current context.
function! kube#kubectl#resource_names_sync(kind, namespace) abort
  let names = s:kubectl_sync(s:context, ['get', a:kind, '-o', 'name'] + s:namespace_args(a:namespace))
  return map(names, 'substitute(v:val, "^[^/]*/", "", "")')
endfunction
