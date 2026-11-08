function! s:format(kind, data, ...) abort
  return kube#format#get(a:kind).fn(a:data, get(a:, 1, {}))
endfunction

function! s:rows(kind, fixture, ...) abort
  return s:format(a:kind, t#json(a:fixture), get(a:, 1, {}))
endfunction

call t#describe('formatters lookup')

function! s:test_lookup() abort
  call assert_true(kube#format#get('po') is kube#format#get('pods'))
  call assert_true(kube#format#get('deployments.apps') is kube#format#get('deploy'))
  call assert_true(kube#format#get('unknownthings') is kube#format#get('default'))
endfunction
call t#it('resolves aliases and falls back to the default', function('s:test_lookup'))

call t#describe('pods formatter')

function! s:test_pods() abort
  let result = s:rows('pods', 'pods.json')
  call assert_equal(['ns1', 'web-1', '2/2', 'Running', '3', '10.0.0.1', 'node-1'], result[0].row[0:6])
  call assert_equal({'STATUS': 'KubeRunning', 'RESTARTS': 'KubePending'}, result[0].highlights)
  call assert_equal(['ns1', 'web-2', '0/1', 'Pending', '0', '', ''], result[1].row[0:6])
  call assert_equal({'STATUS': 'KubePending'}, result[1].highlights)
endfunction
call t#it('formats ready, restarts and status', function('s:test_pods'))

function! s:test_pods_diagnostics() abort
  let result = s:rows('pods', 'pods.json')
  call assert_equal([], result[0].diagnostics)
  call assert_equal([{'message': 'The pod is not ready: 0/3 nodes are available', 'severity': 'warn'}], result[1].diagnostics)
endfunction
call t#it('reports diagnostics for pods that are not ready', function('s:test_pods_diagnostics'))

function! s:test_terminating() abort
  let data = t#json('pods.json')
  let data.items[0].metadata.deletionTimestamp = '2026-01-01T00:00:00Z'
  let data.items[0].status.conditions = [{'type': 'Ready', 'status': 'False', 'reason': 'PodCompleted'}]
  let row = s:format('pods', data)[0]
  call assert_equal('Terminating', row.row[3])
  call assert_equal('KubePending', row.highlights.STATUS)
  call assert_equal('info', row.diagnostics[0].severity)
endfunction
call t#it('shows pods being deleted as terminating, like kubectl', function('s:test_terminating'))

function! s:test_unready_containers() abort
  let data = t#json('pods.json')
  let data.items[0].status.containerStatuses[0].ready = v:false
  let highlights = s:format('pods', data)[0].highlights
  call assert_equal('KubeRunning', highlights.STATUS)
  call assert_equal('KubePending', highlights.READY)
endfunction
call t#it('marks the readiness of running pods with unready containers as pending', function('s:test_unready_containers'))

function! s:status_of(mutate) abort
  let data = t#json('pods.json')
  execute a:mutate
  let row = s:format('pods', data)[0]
  return [row.row[3], row.highlights.STATUS]
endfunction

function! s:test_failing_containers() abort
  let pod = 'data.items[0]'
  call assert_equal(['CrashLoopBackOff', 'KubeFailed'],
        \ s:status_of('let ' . pod . '.status.containerStatuses[1].state = {"waiting": {"reason": "CrashLoopBackOff"}}'))
  call assert_equal(['Error', 'KubeFailed'],
        \ s:status_of('let ' . pod . '.status.containerStatuses[0].state = {"terminated": {"exitCode": 1, "reason": "Error"}}'))
  call assert_equal(['Init:0/1', 'KubePending'],
        \ s:status_of('let ' . pod . '.status.initContainerStatuses[0].state = {"running": {}}'))
  call assert_equal(['Init:ImagePullBackOff', 'KubeFailed'],
        \ s:status_of('let ' . pod . '.status.initContainerStatuses[0].state = {"waiting": {"reason": "ImagePullBackOff"}}'))
  " A started sidecar does not block the pod
  call assert_equal(['Running', 'KubeRunning'], s:status_of(join([
        \ 'let ' . pod . '.spec.initContainers[0].restartPolicy = "Always"',
        \ 'let ' . pod . '.status.initContainerStatuses[0].started = v:true',
        \ 'let ' . pod . '.status.initContainerStatuses[0].state = {"running": {}}'], ' | ')))
  call assert_equal(['Evicted', 'KubeFailed'], s:status_of(join([
        \ 'let ' . pod . '.status.phase = "Failed"',
        \ 'let ' . pod . '.status.reason = "Evicted"',
        \ 'call remove(' . pod . '.status, "containerStatuses")'], ' | ')))
endfunction
call t#it('shows the reason of failing containers, like kubectl', function('s:test_failing_containers'))

function! s:test_not_ready_once() abort
  let data = t#json('pods.json')
  let data.items[0].status.conditions = [{'type': 'Ready', 'status': 'False', 'message': 'containers not ready'}]
  call assert_equal([{'message': 'The pod is not ready: containers not ready', 'severity': 'error'}],
        \ s:format('pods', data)[0].diagnostics)
endfunction
call t#it('reports a pod that is not ready once', function('s:test_not_ready_once'))

call t#describe('containers formatter')

function! s:test_containers() abort
  let result = s:rows('containers', 'pod-web-1.json')
  call assert_equal(['init', 'init', 'Completed', '0', 'busybox:1', ''], result[0].row)
  call assert_equal(['app', 'main', 'Running', '1', 'web:1', '8080/TCP, 9090/TCP'], result[1].row)
  call assert_equal(['sidecar', 'main', 'Running', '2', 'proxy:1', ''], result[2].row)
  call assert_equal({'STATUS': 'KubeSucceeded'}, result[0].highlights)
  call assert_equal({'STATUS': 'KubeRunning', 'RESTARTS': 'KubePending'}, result[1].highlights)
  call assert_equal('app', result[1].item.name)
endfunction
call t#it('lists init containers first, with status, restarts and ports', function('s:test_containers'))

function! s:test_containers_unknown() abort
  call assert_equal('Unknown', s:rows('containers', 'pod-web-2.json')[0].row[2])
endfunction
call t#it('reports unknown when there is no status', function('s:test_containers_unknown'))

function! s:test_containers_reasons() abort
  let pod = t#json('pod-web-1.json')
  let pod.spec.initContainers[0].restartPolicy = 'Always'
  let pod.status.containerStatuses[0].state = {'waiting': {'reason': 'CrashLoopBackOff'}}
  let pod.status.containerStatuses[1].state = {'terminated': {'exitCode': 137, 'reason': 'OOMKilled'}}
  let result = s:format('containers', pod)
  call assert_equal('sidecar', result[0].row[1])
  call assert_equal(['CrashLoopBackOff', 'KubeFailed'], [result[1].row[2], result[1].highlights.STATUS])
  call assert_equal(['OOMKilled', 'KubeFailed'], [result[2].row[2], result[2].highlights.STATUS])
endfunction
call t#it('shows the reason of waiting and terminated containers, and sidecars', function('s:test_containers_reasons'))

call t#describe('deployments formatter')

function! s:test_deployments() abort
  call assert_equal(['ns1', 'web', '1/2', '3', '2', '1'], s:rows('deployments', 'deployments.json')[0].row[0:5])
endfunction
call t#it('formats replica counts, DESIRED from the spec', function('s:test_deployments'))

call t#describe('nodes formatter')

function! s:test_nodes() abort
  let data = t#json('nodes.json')
  let data.items[1].spec.unschedulable = v:true
  let data.items[1].status.conditions = [{'type': 'MemoryPressure', 'status': 'False'}, {'type': 'Ready', 'status': 'False'}]
  let result = s:format('nodes', data)
  call assert_equal(['Ready', 'KubeRunning'], [result[0].row[1], result[0].highlights.STATUS])
  call assert_equal(['NotReady,SchedulingDisabled', 'KubeFailed'], [result[1].row[1], result[1].highlights.STATUS])
  call assert_equal('error', result[1].diagnostics[0].severity)
endfunction
call t#it('shows readiness and cordoned nodes, like kubectl', function('s:test_nodes'))

call t#describe('jobs formatter')

function! s:test_jobs() abort
  let result = s:rows('jobs', 'jobs.json')
  call assert_equal(['ns1', 'migrate', 'Complete', '1/1', '1m5s'], result[0].row[0:4])
  call assert_equal({'STATUS': 'KubeSucceeded'}, result[0].highlights)
  call assert_equal(['ns1', 'backup', 'Failed', '0/1 of 2'], result[1].row[0:3])
  call assert_equal([{'message': 'Job has reached the specified backoff limit', 'severity': 'error'}], result[1].diagnostics)
endfunction
call t#it('formats status, completions and duration, like kubectl', function('s:test_jobs'))

call t#describe('gateways formatter')

function! s:test_gateways() abort
  call assert_equal('a.example.com,b.example.com', s:rows('gateways', 'gateways.json')[0].row[2])
endfunction
call t#it('lists unique sorted hosts', function('s:test_gateways'))

call t#describe('default formatter')

function! s:test_default() abort
  call assert_equal(['ns1', 'web'], s:rows('somethings', 'deployments.json')[0].row[0:1])
endfunction
call t#it('formats namespace, name and age', function('s:test_default'))

call t#describe('portforward formatter')

function! s:clear_forwards() abort
  call kube#portforward#stop_all()
endfunction
call t#after_each(function('s:clear_forwards'))

function! s:test_portforward() abort
  let forwards = kube#portforward#all()
  let forwards[kube#utils#portforward_key('a', 'ns1', 'pod', 'web-1')] = {
        \ '9000': {'container_port': 9090, 'job': {}},
        \ '8000': {'container_port': 8080, 'job': {}},
        \ }
  let forwards[kube#utils#portforward_key('b', 'ns1', 'pod', 'web-1')] = {'7000': {'container_port': 8080, 'job': {}}}
  let result = s:rows('portforward', 'pod-web-1.json', {'context': 'a'})
  call assert_equal(['ns1', 'Pod/web-1', '8000', '8080', 'http://localhost:8000'], result[0].row)
  call assert_equal('9000', result[1].row[2])
  call assert_equal(2, len(result))
endfunction
call t#it("lists the forwards of the resource in the buffer's context only", function('s:test_portforward'))

call t#describe('format_table')

function! s:test_align() abort
  let [header, formatted] = resource#table#format(['NAME', 'AGE'],
        \ [{'row': ['a-long-name', '1d'], 'item': {}}, {'row': ['b', '10d'], 'item': {}}])
  call assert_equal('NAME         AGE', header)
  call assert_equal('a-long-name  1d ', formatted[0].formatted)
  call assert_equal('b            10d', formatted[1].formatted)
endfunction
call t#it('aligns columns to the widest value', function('s:test_align'))

function! s:test_truncate() abort
  call assert_equal(repeat('x', 96) . '...', resource#table#format(['X'], [{'row': [repeat('x', 120)]}])[1][0].formatted)
endfunction
call t#it('truncates columns wider than 99', function('s:test_truncate'))

call t#describe('format_table with wide characters')

function! s:test_wide() abort
  let formatted = resource#table#format(['NAME', 'AGE'],
        \ [{'row': ['中文', '1d'], 'item': {}}, {'row': ['abcde', '2d'], 'item': {}}])[1]
  call assert_equal('中文   1d ', formatted[0].formatted)
  call assert_equal('abcde  2d ', formatted[1].formatted)
  call assert_equal([[0, 7], [9, 12]], formatted[0].ranges)
  call assert_equal(repeat('中', 48) . '...', resource#table#format(['X'], [{'row': [repeat('中', 60)]}])[1][0].formatted)
endfunction
call t#it('aligns and truncates by display width', function('s:test_wide'))
