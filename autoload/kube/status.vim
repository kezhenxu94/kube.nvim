" Statuses of pods and containers, as kubectl shows them.

let s:PENDING = ['Pending', 'Waiting', 'ContainerCreating', 'PodInitializing']

function! s:has(dict, key) abort
  return kube#utils#get(a:dict, a:key, v:null) isnot v:null
endfunction

function! s:string(dict, key) abort
  let value = kube#utils#get(a:dict, a:key, v:null)
  return type(value) == v:t_string ? value : v:null
endfunction

" The highlight group of a status.
function! kube#status#highlight(status) abort
  if a:status ==# 'Running'
    return 'KubeRunning'
  elseif a:status ==# 'Completed' || a:status ==# 'Succeeded'
    return 'KubeSucceeded'
  elseif a:status ==# 'Unknown'
    return 'KubeUnknown'
  elseif a:status ==# 'Terminating' || index(s:PENDING, a:status) >= 0 || a:status =~# '^Init:\d'
    return 'KubePending'
  endif
  " CrashLoopBackOff, ImagePullBackOff, Error, OOMKilled, Evicted, Init:Error, ...
  return 'KubeFailed'
endfunction

" The reason of state.terminated of a container status.
function! kube#status#terminated_reason(terminated) abort
  let reason = s:string(a:terminated, 'reason')
  if !empty(reason)
    return reason
  endif
  let signal = kube#utils#get(a:terminated, 'signal', 0)
  if signal != 0
    return 'Signal:' . signal
  endif
  return 'ExitCode:' . kube#utils#get(a:terminated, 'exitCode', 0)
endfunction

" The status of a container and its highlight group: [status, highlight].
function! kube#status#container(container_status) abort
  let state = kube#utils#get(a:container_status, 'state', {})
  if s:has(state, 'running')
    return ['Running', 'KubeRunning']
  elseif s:has(state, 'waiting')
    let reason = s:string(state.waiting, 'reason')
    let reason = reason is v:null ? 'Waiting' : reason
    return [reason, kube#status#highlight(reason)]
  elseif s:has(state, 'terminated')
    let exit_code = kube#utils#get(state.terminated, 'exitCode', v:null)
    return [kube#status#terminated_reason(state.terminated),
          \ type(exit_code) == v:t_number && exit_code == 0 ? 'KubeSucceeded' : 'KubeFailed']
  endif
  return ['Unknown', 'KubeUnknown']
endfunction

" The status of a pod, like the STATUS column of kubectl get pods.
function! kube#status#pod(pod) abort
  let status = kube#utils#get(a:pod, 'status', {})
  let reason = s:string(status, 'reason')
  if reason is v:null
    let reason = kube#utils#get(status, 'phase', 'Unknown')
  endif

  let init_containers = kube#utils#list(a:pod.spec, 'initContainers')
  let init_specs = {}
  for container in init_containers
    let init_specs[container.name] = container
  endfor

  let initializing = 0
  let i = 0
  for container_status in kube#utils#list(status, 'initContainerStatuses')
    let state = kube#utils#get(container_status, 'state', {})
    let spec = get(init_specs, container_status.name, {})
    let terminated = kube#utils#get(state, 'terminated', {})
    let exit_code = kube#utils#get(terminated, 'exitCode', v:null)
    if !empty(terminated) && type(exit_code) == v:t_number && exit_code == 0
      " Done
    elseif kube#utils#get(spec, 'restartPolicy', '') ==# 'Always' && kube#utils#get(container_status, 'started', 0)
      " A started sidecar does not block the pod
    else
      let initializing = 1
      let waiting_reason = s:string(kube#utils#get(state, 'waiting', {}), 'reason')
      if !empty(terminated)
        let reason = 'Init:' . kube#status#terminated_reason(terminated)
      elseif s:has(state, 'waiting') && waiting_reason isnot v:null && waiting_reason !=# 'PodInitializing'
        let reason = 'Init:' . waiting_reason
      else
        let reason = printf('Init:%d/%d', i, len(init_containers))
      endif
      break
    endif
    let i += 1
  endfor

  if !initializing
    let running = 0
    " Backwards, so that the first container with a reason wins
    for container_status in reverse(copy(kube#utils#list(status, 'containerStatuses')))
      let state = kube#utils#get(container_status, 'state', {})
      let waiting_reason = s:string(kube#utils#get(state, 'waiting', {}), 'reason')
      if s:has(state, 'waiting') && !empty(waiting_reason)
        let reason = waiting_reason
      elseif s:has(state, 'terminated')
        let reason = kube#status#terminated_reason(state.terminated)
      elseif s:has(state, 'running') && kube#utils#get(container_status, 'ready', 0)
        let running = 1
      endif
    endfor
    if reason ==# 'Completed' && running
      let reason = 'Running'
    endif
  endif

  if type(kube#utils#dig(a:pod, 'metadata.deletionTimestamp', v:null)) == v:t_string
    return 'Terminating'
  endif
  return reason
endfunction
