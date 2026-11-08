let g:kube_refresh_interval = 200
let s:PODS = 'kube://context/ctx-a/namespaces/ns1/pods'

function! s:before() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
  call t#respond('*get pods -o json*', {'fixture': 'pods.json'})
  call t#respond('*get deployments -o json*', {'fixture': 'deployments.json'})
  call t#respond('*get deployment.apps web -o yaml*', {'fixture': 'deployment-web.yaml'})
  call t#respond('*get secrets -o json*', {'fixture': 'secrets.json'})
  call t#respond('*get secret -o json db *', {'fixture': 'secret-db.json'})
  call t#respond('*get events -o json*', {'fixture': 'events.json'})
  call t#respond('*get nodes -o json*', {'fixture': 'nodes.json'})
  call t#capture_notify()
endfunction
call t#before_each(function('s:before'))

function! s:after() abort
  call t#restore_stubs()
  call t#clean_buffers()
  call kube#portforward#stop_all()
endfunction
call t#after_each(function('s:after'))

call t#describe('errors')

function! s:test_errors_shown() abort
  let messages = t#capture_notify()
  call t#respond('*get pods -o json*', {'stderr': 'Error from server (Forbidden): pods is forbidden', 'code': 1})
  call t#open('kube://namespaces/ns1/pods')
  call assert_equal('✗ Error from server (Forbidden): pods is forbidden', t#status())
  call assert_equal('Error from server (Forbidden): pods is forbidden', messages[-1].msg)
endfunction
call t#it('are shown in the buffer and notified', function('s:test_errors_shown'))

function! s:test_errors_silent() abort
  call t#open('kube://namespaces/ns1/pods')
  let messages = t#capture_notify()
  call t#respond('*get pods -o json*', {'stderr': 'connection refused', 'code': 1})
  call kube#buffer#load(t#kbuf(), {'silent': 1})
  call t#wait_loaded()
  call assert_equal('✗ connection refused', t#status())
  call assert_equal([], messages)
  call assert_equal(2, line('$'), 'the last rendered list is kept')
endfunction
call t#it('are not notified on background reloads', function('s:test_errors_silent'))

function! s:test_reload_closed() abort
  call t#open('kube://namespaces/ns1/pods')
  let kbuf = t#kbuf()
  bwipeout!
  call kube#buffer#load(kbuf)
endfunction
call t#it('reloading a closed buffer is a no-op', function('s:test_reload_closed'))

function! s:test_wrap() abort
  set wrap
  call t#open('kube://namespaces/ns1/pods')
  call assert_equal(0, &wrap)
  call t#open('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call assert_equal(1, &wrap)
endfunction
call t#it('lists do not wrap, other views do', function('s:test_wrap'))

function! s:test_empty() abort
  call t#respond('*get pods -o json*', {'stdout': '{"items":[]}'})
  call t#open('kube://namespaces/ns1/pods')
  call assert_equal('No resources found', t#status())
endfunction
call t#it('an empty list says so', function('s:test_empty'))

call t#describe('applying YAML')

let s:EDIT = 'kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml'

function! s:before_apply() abort
  call t#respond('*apply*', {'stdout': 'deployment.apps/web configured'})
  call t#open(s:EDIT)
  call setline(6, '  replicas: 3')
endfunction
call t#before_each(function('s:before_apply'))

function! s:diff_shown(items, opts) abort
  for win in range(1, winnr('$'))
    if getbufvar(winbufnr(win), '&filetype') ==# 'diff'
      let g:t_diff = getbufline(winbufnr(win), 1, '$')
    endif
  endfor
  call assert_equal('Apply deployment.apps/web (context: ctx-a)?', a:opts.prompt)
  return 'Yes'
endfunction

function! s:test_apply_confirmed() abort
  call t#respond('*diff*', {'stdout': "-  replicas: 2\n+  replicas: 3\n", 'code': 1})
  let g:t_diff = []
  call t#answer_prompts(function('s:diff_shown'), v:null)
  write
  call t#wait_call('apply')
  call assert_equal(['-  replicas: 2', '+  replicas: 3'], g:t_diff)
  call assert_equal(1, len(t#calls_matching('^--context ctx-a -n ns1 diff -f ')))
  call t#wait_for({-> !&modified}, 'reload')
  call assert_equal(1, winnr('$'), 'diff window is closed')
endfunction
call t#it('shows the diff and applies once confirmed', function('s:test_apply_confirmed'))

function! s:test_apply_declined() abort
  call t#respond('*diff*', {'stdout': "-a\n+b\n", 'code': 1})
  call t#answer_prompts({items, opts -> 'No'}, v:null)
  write
  call t#wait_call('diff')
  call t#wait(100)
  call assert_equal([], t#calls_matching('apply'))
  call assert_equal(1, &modified)
endfunction
call t#it('does not apply when declined', function('s:test_apply_declined'))

function! s:test_apply_force() abort
  write!
  call t#wait_call('apply')
  call assert_equal([], t#calls_matching('diff'))
endfunction
call t#it(':w! applies without the diff', function('s:test_apply_force'))

function! s:test_no_difference() abort
  call t#respond('*diff*', {'stdout': '', 'code': 0})
  write
  call t#wait_for({-> !&modified}, 'reload')
  call assert_equal([], t#calls_matching('apply'))
endfunction
call t#it('reloads without applying when there is no difference', function('s:test_no_difference'))

function! s:test_diff_errors() abort
  let messages = t#capture_notify()
  call t#respond('*diff*', {'stderr': 'error: invalid object', 'code': 2})
  write
  call t#wait_for({-> !empty(messages)}, 'error')
  call assert_equal('Failed to diff: error: invalid object', messages[0].msg)
  call assert_equal(1, &modified)
endfunction
call t#it('reports diff errors and keeps the edits', function('s:test_diff_errors'))

call t#describe(':Kube apply / diff')

function! s:before_manifest() abort
  enew
  call setline(1, ['apiVersion: v1', 'kind: ConfigMap'])
endfunction
call t#before_each(function('s:before_manifest'))

function! s:test_kube_apply() abort
  call t#respond('*diff*', {'stdout': "+kind: ConfigMap\n", 'code': 1})
  call t#respond('*apply*', {'stdout': 'configmap/x created'})
  let seen = t#prompts()
  Kube apply
  call t#wait_call('apply')
  call assert_equal(['Apply buffer (context: ctx-a)?'], seen)
  call assert_equal(1, len(t#calls_matching('^--context ctx-a apply -f .*\.yaml$')))
endfunction
call t#it('apply confirms with the diff in the current context', function('s:test_kube_apply'))

function! s:test_kube_apply_force() abort
  call t#respond('*apply*', {'stdout': 'configmap/x created'})
  Kube! apply
  call t#wait_call('apply')
  call assert_equal([], t#calls_matching('diff'))
endfunction
call t#it('Kube! apply skips the confirmation', function('s:test_kube_apply_force'))

function! s:test_kube_diff() abort
  call t#respond('*diff*', {'stdout': "+kind: ConfigMap\n", 'code': 1})
  Kube diff
  call t#wait_for('winnr("$") == 2', 'diff window')
  call assert_equal([], t#calls_matching('apply'))
endfunction
call t#it('diff shows the differences', function('s:test_kube_diff'))

call t#describe('secrets')

let s:DATA = 'kube://context/ctx-a/namespaces/ns1/secret/db/data'

function! s:test_decoded() abort
  call t#open('kube://namespaces/ns1/secrets')
  call t#press_on('db', "\<CR>")
  call t#wait_buf_name(s:DATA)
  call t#wait_loaded()
  call assert_equal([
        \ 'cert: !!binary "/wAB"',
        \ 'password: "p@ss\"word\nline2"',
        \ 'username: "admin"',
        \ ], t#lines()[len(kube#secret#to_lines({})):])
  call assert_equal(1, &modifiable)
endfunction
call t#it('<CR> shows the decoded data', function('s:test_decoded'))

function! s:test_patch() abort
  call t#respond('*patch*', {'stdout': 'secret/db patched'})
  call t#open(s:DATA)
  let seen = t#prompts()
  let header = len(kube#secret#to_lines({}))
  execute (header + 1) . ',$delete _'
  call append(header, ['password: "p@ss\"word\nline2"', 'username: "root"', 'token: "abc"'])
  write
  call t#wait_call('patch')
  call assert_equal(['Update secret ns1/db (context: ctx-a): added token; changed username; removed cert?'], seen)
  let patch = json_decode(matchlist(t#calls_matching('patch')[0], ' -p \({.*}\) ')[1])
  call assert_equal({'data': {'token': 'YWJj', 'username': 'cm9vdA==', 'cert': v:null}}, patch)
  call assert_equal(1, len(t#calls_matching('^--context ctx-a patch secret db --type=merge -p .* -n ns1$')))
endfunction
call t#it('saving patches added, changed and removed keys', function('s:test_patch'))

function! s:test_invalid_lines() abort
  let messages = t#capture_notify()
  call t#open(s:DATA)
  call append('$', 'broken line')
  write
  call assert_equal('Invalid secret data, line 7: expected `key: "value"`', messages[-1].msg)
  call assert_equal([], t#calls_matching('patch'))
endfunction
call t#it('rejects invalid lines', function('s:test_invalid_lines'))

function! s:test_round_trip() abort
  let data = t#json('secret-db.json').data
  call assert_equal(data, kube#secret#from_lines(kube#secret#to_lines(data))[0])
  call assert_equal('8J+Ym8OpCg==', kube#secret#base64_encode(kube#secret#base64_decode('8J+Ym8OpCg==')))
  call assert_equal(['k: "😛é\n"'], kube#secret#to_lines({'k': '8J+Ym8OpCg=='})[-1:])
  call assert_equal(v:null, kube#secret#base64_decode('abc'))
endfunction
call t#it('round-trips values exactly', function('s:test_round_trip'))

call t#describe('events')

function! s:test_events() abort
  call t#open('kube://namespaces/ns1/events')
  call assert_match('Warning\s\+BackOff\s\+deployment/web\s\+Back-off restarting failed container', getline(1))
  call assert_match('Normal\s\+Pulled\s\+pod/web-1', getline(2))
  let diagnostics = t#diagnostics()
  call assert_equal(1, len(diagnostics))
  call assert_equal(1, diagnostics[0][0])
endfunction
call t#it('lists the most recent first with warnings as diagnostics', function('s:test_events'))

function! s:test_workload_events() abort
  call t#respond('*get deployment.apps -o json web *', {'fixture': 'deployment-web.json'})
  call t#respond('*get pods,replicasets -o json*', {'fixture': 'pods.json'})
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', '')
  call t#operation('Show events')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/events?for=deployment.apps/web')
  call t#wait_for('line("$") == 2', 'events of the deployment and its pods')
  call assert_match('deployment/web', getline(1))
  call assert_match('pod/web-1', getline(2))
  call assert_equal(['--context ctx-a get pods,replicasets -o json -n ns1 --selector=app=web,tier=frontend'],
        \ t#calls_matching('pods,replicasets'))
endfunction
call t#it('of a workload include the pods it selects', function('s:test_workload_events'))

function! s:test_own_events() abort
  call t#respond('*get configmap -o json cfg *', {'stdout': json_encode({'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': 'cfg', 'namespace': 'ns1'}})})
  edit kube://context/ctx-a/namespaces/ns1/events?for=configmap/cfg
  call t#wait_for({-> t#status() is# 'No events: Kubernetes keeps events for 1 hour by default'}, 'the empty status')
  call assert_equal([], t#calls_matching('pods,replicasets'))
endfunction
call t#it('of a resource without a selector are its own', function('s:test_own_events'))

function! s:test_no_events() abort
  call t#respond('*get events -o json*', {'stdout': '{"items":[]}'})
  call t#open('kube://namespaces/ns1/events')
  call assert_equal('No events: Kubernetes keeps events for 1 hour by default', t#status())
endfunction
call t#it('explain why there are none', function('s:test_no_events'))

function! s:test_event_object() abort
  call t#open('kube://namespaces/ns1/events')
  call t#press_on('deployment/web', "\<C-]>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
endfunction
call t#it('<C-]> on the object goes to it', function('s:test_event_object'))

function! s:test_resource_events() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', '')
  call t#operation('Show events')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/events?field-selector=involvedObject.kind=Pod,involvedObject.name=web-1')
  call t#wait_call('get events')
  call assert_equal(1, len(t#calls_matching('get events -o json -n ns1 --field-selector=involvedObject.kind=Pod,involvedObject.name=web-1$')))
endfunction
call t#it('are shown for the resource under the cursor', function('s:test_resource_events'))

call t#describe('operations')

function! s:test_scale() abort
  call t#respond('*scale*', {'stdout': 'deployment.apps/web scaled'})
  call t#answer_prompts(v:null, '3')
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', '')
  call t#operation('Scale…')
  call t#wait_call('scale')
  call assert_equal(['--context ctx-a scale deployment.apps/web --replicas=3 -n ns1'], t#calls_matching('scale'))
  call t#wait_call('get deployments', 2)
endfunction
call t#it('scale', function('s:test_scale'))

function! s:test_restart_undo() abort
  call t#respond('*rollout*', {'stdout': 'ok'})
  let seen = t#prompts()
  call t#answer_prompts({items, opts -> [add(seen, opts.prompt), 'Yes'][1]}, v:null)
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', '')
  call t#operation('Restart')
  call t#wait_call('rollout restart')
  call t#operation('Undo rollout')
  call t#wait_call('rollout undo')
  call assert_equal([
        \ 'Restart deployment.apps/web (context: ctx-a)?',
        \ 'Undo the rollout of deployment.apps/web (context: ctx-a)?',
        \ ], seen)
  call assert_equal([
        \ '--context ctx-a rollout restart deployment.apps/web -n ns1',
        \ '--context ctx-a rollout undo deployment.apps/web -n ns1',
        \ ], t#calls_matching('rollout'))
endfunction
call t#it('restart and undo confirm with the context', function('s:test_restart_undo'))

function! s:test_history() abort
  call t#respond('*rollout history*', {'stdout': "REVISION  CHANGE-CAUSE\n1         <none>\n"})
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', '')
  call t#operation('Rollout history')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps/web/history')
  call t#wait_loaded()
  call assert_equal(['REVISION  CHANGE-CAUSE', '1         <none>'], t#lines())
endfunction
call t#it('rollout history', function('s:test_history'))

function! s:test_logs_options() abort
  call t#respond('*logs*', {'stdout': "line1\n"})
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', '')
  call t#operation('Show logs of the previous instance')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?previous=true')
  call t#wait_call('logs')
  call assert_equal(['--context ctx-a logs pod/web-1 -n ns1 --tail=1000 --previous'], t#calls_matching('logs'))
endfunction
call t#it('logs with options', function('s:test_logs_options'))

function! s:test_trigger() abort
  call t#respond('*get cronjobs -o json*', {'stdout': json_encode({'items': [{
        \ 'apiVersion': 'batch/v1',
        \ 'kind': 'CronJob',
        \ 'metadata': {'name': 'report', 'namespace': 'ns1', 'creationTimestamp': '2026-01-01T00:00:00Z'},
        \ 'spec': {'schedule': '0 * * * *'},
        \ 'status': {},
        \ }]})})
  call t#respond('*create job*', {'stdout': 'job.batch/report-manual-1 created'})
  let seen = t#prompts()
  call t#open('kube://namespaces/ns1/cronjobs')
  call t#press_on('report', '')
  call t#operation('Trigger now')
  call t#wait_call('create job')
  call assert_equal(['Trigger cronjob.batch/report (context: ctx-a)?'], seen)
  call assert_match('^--context ctx-a create job report-manual-\d\+ --from=cronjob/report -n ns1$', t#calls_matching('create job')[0])
endfunction
call t#it('trigger a cron job now', function('s:test_trigger'))

function! s:test_debug() abort
  call t#respond('*debug*', {'script': 'sleep 30'})
  call t#answer_prompts({items, opts -> items[1]}, 'nicolaka/netshoot')
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', '')
  call t#operation('Debug (ephemeral container)')
  call t#wait_call('debug')
  stopinsert
  call assert_equal(['--context ctx-a debug -it pod/web-1 --image=nicolaka/netshoot -n ns1 --target=sidecar -- sh'], t#calls_matching('debug'))
  call assert_equal('kube://context/ctx-a/namespaces/ns1/pod/web-1/debug?image=nicolaka/netshoot&target=sidecar', bufname(''))
endfunction
call t#it('debug a pod in an ephemeral container', function('s:test_debug'))

function! s:test_range() abort
  call t#respond('*delete*', {'stdout': 'deleted'})
  let seen = t#prompts()
  call t#open('kube://namespaces/ns1/pods')
  call t#operation('Delete 2 resources', 1, 2)
  call t#wait_call('delete', 2)
  call assert_equal(['Delete pod/web-1, pod/web-2 (context: ctx-a)?'], seen)
endfunction
call t#it('on a range apply to all selected resources', function('s:test_range'))

function! s:test_nodes() abort
  call t#respond('*cordon*', {'stdout': 'cordoned'})
  call t#respond('*drain*', {'stdout': 'drained'})
  let seen = t#prompts()
  call t#open('kube://nodes')
  call t#operation('Cordon 2 resources', 1, 2)
  call t#wait_call('cordon', 2)
  call assert_equal([], seen, 'cordon is not confirmed')
  call t#press_on('node-2', '')
  call t#operation('Drain')
  call t#wait_call('drain')
  call assert_equal(['Drain node/node-2 (context: ctx-a)?'], seen)
  call assert_equal(['--context ctx-a drain node-2 --ignore-daemonsets --delete-emptydir-data'], t#calls_matching('drain'))
endfunction
call t#it('on nodes', function('s:test_nodes'))

function! s:titles(kbuf, items) abort
  return map(kube#operations#for_items(a:kbuf, a:items), 'v:val.title')
endfunction

function! s:test_by_kind() abort
  call t#open('kube://namespaces/ns1/pods')
  let kbuf = t#kbuf()
  let pod = t#json('pod-web-1.json')
  let deployment = t#json('deployments.json').items[0]
  call assert_notequal(-1, index(s:titles(kbuf, [pod]), 'Exec'))
  call assert_equal(-1, index(s:titles(kbuf, [pod]), 'Scale…'))
  call assert_notequal(-1, index(s:titles(kbuf, [deployment]), 'Scale…'))
  call assert_equal(['Delete 2 resources'], s:titles(kbuf, [pod, deployment]), 'mixed kinds only share delete')
endfunction
call t#it('are offered by kind', function('s:test_by_kind'))

function! s:test_gra() abort
  call t#respond('*delete*', {'stdout': 'deleted'})
  let g:t_offered = []
  call t#answer_prompts({items, opts -> index(items, 'Yes') >= 0 ? 'Yes' : [extend(g:t_offered, items), 'Delete'][1]}, v:null)
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-2', 'gra')
  call assert_equal('Open', g:t_offered[0])
  call t#wait_call('delete')
  call assert_equal(['--context ctx-a delete pod web-2 -n ns1'], t#calls_matching('delete'))
endfunction
call t#it('gra selects the operation to run on the resource under the cursor', function('s:test_gra'))

call t#describe('resource types')

function! s:test_resource_types() abort
  call t#respond('*api-resources*', {'fixture': 'api-resources.txt'})
  call t#respond('*get events*', {'stdout': '{"items":[]}'})
  call t#respond('*get deployments.apps*', {'fixture': 'deployments.json'})
  call t#open('kube://ns/ns1/api-resources')
  call search('deployments')
  call t#operation('Show events')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/events?field-selector=involvedObject.kind=Deployment')
  execute "normal! \<C-o>"
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/api-resources')
  call search('deployments')
  call t#operation('List in all namespaces')
  call t#wait_buf_name('kube://context/ctx-a/deployments.apps')
endfunction
call t#it('offer listing them, in all namespaces, and their events', function('s:test_resource_types'))

call t#describe('global port forwards')

function! s:forward(name, local_port) abort
  let g:t_asked = 0
  call t#answer_prompts({items, opts -> g:t_asked ? v:null : [execute('let g:t_asked = 1'), items[0]][1]}, string(a:local_port))
  call t#open(a:name)
  call t#press_on('web-1', 'gf')
endfunction

function! s:test_global_forwards() abort
  call t#respond('*port-forward*', {'script': 'sleep 30'})
  call s:forward('kube://context/ctx-a/namespaces/ns1/pods', 18080)
  call s:forward('kube://context/ctx-b/namespaces/ns1/pods', 28080)
  call t#restore_stubs()
  call t#capture_notify()

  Kube portforwards
  call t#wait_buf_name('kube://portforwards')
  call assert_equal(2, line('$'))
  call assert_match('^ctx-a\s\+ns1\s\+pod/web-1\s\+18080\s\+8080\s\+http://localhost:18080', getline(1))
  call assert_match('^ctx-b', getline(2))

  let job = kube#portforward#all()['ctx-b/ns1/pod/web-1'][28080].job
  call t#answer_prompts({items, opts -> 'Yes'}, v:null)
  call t#press_on('ctx-b', 'dd')
  write
  call t#wait_for({-> !kube#compat#running(job) && line('$') == 1}, 'forward to stop')
  call assert_true(has_key(kube#portforward#all()['ctx-a/ns1/pod/web-1'], 18080), 'the other forward is kept')
endfunction
call t#it('lists forwards of all contexts, deleting a line stops it', function('s:test_global_forwards'))

function! s:test_forward_operations() abort
  call t#respond('*port-forward*', {'script': 'sleep 30'})
  call t#respond('*get pod web-1 -o yaml*', {'stdout': 'kind: Pod'})
  call t#answer_prompts({items, opts -> items[0]}, '18080')
  call t#open('kube://context/ctx-a/namespaces/ns1/pods')
  call t#press_on('web-1', 'gf')
  let key = 'ctx-a/ns1/pod/web-1'
  call t#wait_for({-> has_key(get(kube#portforward#all(), key, {}), 18080)}, 'port forward')
  let job = kube#portforward#all()[key][18080].job

  edit kube://portforwards
  call t#operation('Go to pod/web-1')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml')
  execute "normal! \<C-o>"
  call t#wait_buf_name('kube://portforwards')

  call t#answer_prompts({items, opts -> 'Yes'}, v:null)
  call t#operation('Stop')
  call t#wait_for({-> !kube#compat#running(job)}, 'forward to stop')
  call assert_false(has_key(kube#portforward#all()[key], 18080))
endfunction
call t#it('offer stopping them and going to the forwarded resource', function('s:test_forward_operations'))

call t#describe('watch')

function! s:test_watch() abort
  call t#open('kube://namespaces/ns1/pods')
  call assert_equal(1, len(t#calls_matching('get pods')))

  call t#press('gw')
  call assert_match('⟳ 0.2s', kube#compat#header(bufnr(''), win_getid()))
  call t#wait_call('get pods', 3)

  normal! dd
  let paused = len(t#calls_matching('get pods'))
  call t#wait(500)
  call assert_equal(paused, len(t#calls_matching('get pods')), 'no reload while modified')
  normal! u

  call t#press('gw')
  call assert_notmatch('⟳', kube#compat#header(bufnr(''), win_getid()))
  call t#wait(300)
  let stopped = len(t#calls_matching('get pods'))
  call t#wait(500)
  call assert_equal(stopped, len(t#calls_matching('get pods')), 'no reload once toggled off')
endfunction
call t#it('gw toggles periodic reloads, paused while the buffer is modified', function('s:test_watch'))

function! s:test_watch_lists() abort
  let messages = t#capture_notify()
  call t#open('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call t#press('gw')
  call assert_equal('Only resource lists can be watched', messages[-1].msg)
endfunction
call t#it('is only for lists', function('s:test_watch_lists'))

call t#describe('keymaps')

function! s:test_after_edit() abort
  call t#open('kube://namespaces/ns1/pods')
  edit
  call t#wait_loaded()
  call assert_equal(1, maparg('g?', 'n', 0, 1).buffer, 'buffer keymaps')
endfunction
call t#it('stay after :e reloads the buffer', function('s:test_after_edit'))

function! s:test_owner() abort
  let pods = t#json('pods.json')
  let pods.items[0].metadata.ownerReferences = [
        \ {'apiVersion': 'v1', 'kind': 'Node', 'name': 'node-1'},
        \ {'apiVersion': 'apps/v1', 'kind': 'ReplicaSet', 'name': 'web-abc', 'controller': v:true},
        \ ]
  call t#respond('*get pods -o json*', {'stdout': json_encode(pods)})
  call t#open(s:PODS)
  call t#press_on('web-1', 'gD')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/replicaset.apps/web-abc?output=yaml')
endfunction
call t#it('gD goes to the owner, the controller first', function('s:test_owner'))

function! s:test_owner_yaml() abort
  let deployment = t#json('deployment-web.json')
  let deployment.metadata.ownerReferences = [{'apiVersion': 'example.com/v1', 'kind': 'App', 'name': 'web'}]
  call t#respond('*get deployment.apps -o json web *', {'stdout': json_encode(deployment)})
  call t#open('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call t#press('gD')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/app.example.com/web?output=yaml')
endfunction
call t#it('gD in a YAML buffer goes to the owner of its resource', function('s:test_owner_yaml'))

function! s:test_diagnostic_keys() abort
  call t#open(s:PODS)
  call cursor(1, 1)
  call t#press(']d')
  call assert_equal(2, line('.'))
  call t#press('[d')
  call assert_equal(2, line('.'), 'no unhealthy resource above')
  call t#press("\<C-w>d")
  let float = t#wait_float('The pod is not ready: 0/3 nodes are available')
  call kube#compat#close_float(float)
endfunction
call t#it(']d goes to the next unhealthy resource, <C-w>d shows why', function('s:test_diagnostic_keys'))

call t#describe('pods using')

function! s:test_pods_using() abort
  let pods = t#json('pods.json')
  let pods.items[1].spec.containers[0].envFrom = [{'secretRef': {'name': 'db'}}]
  call t#respond('*get pods -o json*', {'stdout': json_encode(pods)})
  call t#open('kube://context/ctx-a/namespaces/ns1/pods?using=secret/db')
  call assert_equal(1, line('$'))
  call assert_match('web-2', getline(1))
endfunction
call t#it('lists the pods using a resource', function('s:test_pods_using'))

function! s:test_pods_using_node() abort
  call t#open('kube://context/ctx-a/pods?using=node/node-1')
  call assert_equal(1, line('$'))
  call assert_equal(1, len(t#calls_matching('get pods -o json --all-namespaces --field-selector=spec.nodeName=node-1')))
endfunction
call t#it('lists the pods of all namespaces on a node', function('s:test_pods_using_node'))

call t#describe('lists')

" Put the cursor on the {column} cell of the row of {name} and type {keys}.
function! s:edit_cell(name, column, keys) abort
  let kbuf = t#kbuf()
  let cells = kube#compat#cells(kbuf.bufnr)
  for [id, cell] in items(kbuf.cells)
    let item = cell.item
    let item_name = type(item) != v:t_dict ? '' : has_key(item, 'metadata') ? item.metadata.name : get(item, 'name', '')
    if cell.column ==# a:column && item_name ==# a:name
      call cursor(cells[id][0], cells[id][1] + 1)
      call t#press(a:keys)
      return
    endif
  endfor
  throw printf('no %s cell for %s', a:column, a:name)
endfunction

function! s:test_header_sign_column() abort
  if !has('nvim')
    call t#skip('Vim has no winbar, the header is above the first line')
  endif
  call t#open(s:PODS)
  call assert_true(!empty(t#diagnostics()), 'an unhealthy pod')
  let textoff = getwininfo(win_getid())[0].textoff
  call assert_true(textoff > 0, 'a sign column')
  call assert_equal(repeat(' ', textoff) . '%#', &winbar[: textoff + 1])
endfunction
call t#it('align the header with the sign column of the diagnostics', function('s:test_header_sign_column'))

function! s:test_header_vim() abort
  if has('nvim')
    call t#skip('Neovim shows the header in the winbar')
  endif
  call t#open(s:PODS)
  call assert_match('^NAMESPACE\s\+NAME\s\+READY', kube#compat#header(bufnr(''), win_getid()))
  call t#press_on('web-1', 'dd')
  doautocmd TextChanged
  call assert_match('^NAMESPACE', kube#compat#header(bufnr(''), win_getid()), 'shown when the first line is deleted')
endfunction
call t#it('show the header above the first line in Vim', function('s:test_header_vim'))

function! s:test_deleted_rows() abort
  call t#open(s:PODS)
  " Like typing, so that each delete can be undone
  let &undolevels = &undolevels
  call t#press_on('web-1', 'dd')
  doautocmd TextChanged
  let marks = kube#compat#get_virt_lines(bufnr(''))
  call assert_equal(1, len(marks))
  call assert_equal(1, marks[0][0])
  call assert_equal(1, marks[0][2], 'above')
  call assert_match('^ns1\s\+web-1\s\+2/2', marks[0][1][0])
  if has('nvim')
    call assert_equal(1, winsaveview().topfill, 'scrolled to show the line above the first one')
  endif

  let &undolevels = &undolevels
  call t#press_on('web-2', 'dd')
  doautocmd TextChanged
  let marks = kube#compat#get_virt_lines(bufnr(''))
  call assert_equal(1, len(marks), 'below the last line')
  call assert_equal(2, len(marks[0][1]))
  call assert_equal(0, marks[0][2])

  silent normal! uu
  doautocmd TextChanged
  call assert_equal([], kube#compat#get_virt_lines(bufnr('')))
endfunction
call t#it('show deleted rows until they are written or restored', function('s:test_deleted_rows'))

function! s:highlighted(hl_filter) abort
  let kbuf = t#kbuf()
  let result = []
  for [id, cell] in items(kube#compat#cells(kbuf.bufnr))
    if !empty(cell[3]) && cell[3] =~# a:hl_filter
      let c = kbuf.cells[id]
      call add(result, printf('%s %s %s', c.item.metadata.name, c.column, cell[3]))
    endif
  endfor
  return sort(result)
endfunction

function! s:test_cell_highlights() abort
  call t#open(s:PODS)
  call assert_equal(['web-1 RESTARTS KubePending', 'web-1 STATUS KubeRunning', 'web-2 STATUS KubePending'], s:highlighted('.'))
endfunction
call t#it('highlight cells rather than rows', function('s:test_cell_highlights'))

function! s:test_editable_highlights() abort
  call t#open('kube://namespaces/ns1/deployments')
  let editable = s:highlighted('KubeEditable')
  call assert_true(!empty(editable))
  call assert_equal(['DESIRED'], uniq(sort(map(editable, 'split(v:val)[1]'))))
endfunction
call t#it('highlight the cells of editable columns', function('s:test_editable_highlights'))

function! s:test_flash() abort
  call t#open(s:PODS)
  let kbuf = t#kbuf()

  " Only the order changed
  call t#respond('*get pods -o json*', {'fixture': 'pods-reversed.json'})
  call kube#buffer#load(kbuf, {'silent': 1})
  call t#wait_loaded()
  call assert_equal([], kube#compat#highlighted_lines(bufnr(''), 'changed'))

  let data = t#json('pods.json')
  let data.items[1].status.phase = 'Failed'
  call t#respond('*get pods -o json*', {'stdout': json_encode(data)})
  call kube#buffer#load(kbuf, {'silent': 1})
  call t#wait_loaded()
  let lines = kube#compat#highlighted_lines(bufnr(''), 'changed')
  call assert_equal(1, len(lines))
  call assert_match('web-2', getline(lines[0]))
  call t#wait_for({-> empty(kube#compat#highlighted_lines(bufnr(''), 'changed'))}, 'the flash to end')

  " A reload asked for does not flash
  let data.items[1].status.phase = 'Pending'
  call t#respond('*get pods -o json*', {'stdout': json_encode(data)})
  call kube#buffer#load(kbuf)
  call t#wait_loaded()
  call assert_equal([], kube#compat#highlighted_lines(bufnr(''), 'changed'))
endfunction
call t#it('flash the rows a watched reload changed', function('s:test_flash'))

call t#describe('editing cells')

function! s:test_scale_cell() abort
  call t#respond('*scale*', {'stdout': 'deployment.apps/web scaled'})
  let seen = t#prompts()
  call t#open('kube://namespaces/ns1/deployments')
  call s:edit_cell('web', 'DESIRED', "ciw5\<Esc>")
  write
  call t#wait_call('scale')
  call assert_equal(["Apply the changes (context: ctx-a)?\n  Scale deployment.apps/web: 3 → 5"], seen)
  call assert_equal(['--context ctx-a scale deployment.apps/web --replicas=5 -n ns1'], t#calls_matching('scale'))
  call t#wait_call('get deployments', 2)
endfunction
call t#it('scales after confirming the edited DESIRED', function('s:test_scale_cell'))

function! s:test_edits_and_deletes() abort
  call t#respond('*scale*', {'stdout': 'scaled'})
  call t#respond('*delete*', {'stdout': 'deleted'})
  let data = t#json('deployments.json')
  let api = deepcopy(data.items[0])
  let api.metadata.name = 'api'
  call add(data.items, api)
  call t#respond('*get deployments -o json*', {'stdout': json_encode(data)})
  let seen = t#prompts()
  call t#open('kube://namespaces/ns1/deployments')
  call s:edit_cell('web', 'DESIRED', "ciw0\<Esc>")
  call t#press_on('api', 'dd')
  write!
  call t#wait_call('scale')
  call t#wait_call('delete')
  call assert_equal([], seen)
  call assert_equal(['--context ctx-a delete deployment.apps api -n ns1'], t#calls_matching('delete'))
endfunction
call t#it('applies edits and deletes together, :w! without confirming', function('s:test_edits_and_deletes'))

function! s:test_invalid_value() abort
  let messages = t#capture_notify()
  call t#open('kube://namespaces/ns1/deployments')
  call s:edit_cell('web', 'DESIRED', "ciw-1\<Esc>")
  write
  call assert_equal('Invalid number of replicas for deployment.apps/web: -1', messages[-1].msg)
  call assert_equal('error', messages[-1].level)
  call assert_equal([], t#calls_matching('scale'))
  call assert_equal(1, &modified)
endfunction
call t#it('rejects invalid values and keeps the edits', function('s:test_invalid_value'))

function! s:test_not_editable() abort
  let messages = t#capture_notify()
  call t#open('kube://namespaces/ns1/pods')
  call s:edit_cell('web-1', 'NAMESPACE', "ciwns2\<Esc>")
  write
  call assert_equal('NAMESPACE of pod/web-1 is not editable', messages[-1].msg)
  call assert_equal('error', messages[-1].level)
  call assert_equal(1, &modified)
endfunction
call t#it('rejects edits of other columns and keeps the edits', function('s:test_not_editable'))

function! s:test_image_cell() abort
  call t#respond('*get pod -o json web-1 *', {'fixture': 'pod-web-1.json'})
  call t#respond('*set image*', {'stdout': 'pod/web-1 image updated'})
  call t#open('kube://namespaces/ns1/pod/web-1/containers')
  call s:edit_cell('app', 'IMAGE', "cWweb:2\<Esc>")
  write!
  call t#wait_call('set image')
  call assert_equal(['--context ctx-a set image pod/web-1 app=web:2 -n ns1'], t#calls_matching('set image'))
endfunction
call t#it('sets the image of a container', function('s:test_image_cell'))

call t#describe('metrics')

function! s:test_metrics() abort
  call t#respond('*top pods*', {'stdout': "web-1   12m   34Mi\n"})
  call t#open(s:PODS)
  call assert_equal(['--context ctx-a top pods --no-headers -n ns1'], t#calls_matching('top'))
  call assert_match('NODE\s\+CPU\s\+MEMORY\s\+AGE', t#kbuf().header_row.formatted)
  call assert_match('^ns1\s\+web-1 .* node-1\s\+12m\s\+34Mi\s\+\d', getline(1))
  call assert_match('Pending\s\+0\s\+\d\+[smhd]', getline(2))
endfunction
call t#it('adds CPU and MEMORY columns from kubectl top', function('s:test_metrics'))

function! s:test_no_metrics() abort
  call t#respond('*top nodes*', {'stderr': 'error: Metrics API not available', 'code': 1})
  call t#open('kube://context/ctx-c/nodes')
  call assert_match('^node-1\s\+Ready', getline(1))
  normal R
  call t#wait_loaded()
  call assert_equal(2, len(t#calls_matching('get nodes')))
  call assert_equal(1, len(t#calls_matching('top nodes')))
endfunction
call t#it('are not asked again when the cluster has no metrics API', function('s:test_no_metrics'))

call t#describe('following logs')

function! s:test_follow_end() abort
  let g:kube_logs_max_lines = 3
  try
    call t#respond('*logs*', {'script': "printf 'a\\nb\\n'; sleep 0.2; printf 'c\\nd\\ne\\n'; sleep 30"})
    edit kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true
    call t#wait_for({-> getline(1) ==# 'c'}, 'the oldest lines to be dropped')
    call assert_equal(['c', 'd', 'e', ''], t#lines())
    call assert_equal(4, line('.'))
  finally
    unlet g:kube_logs_max_lines
  endtry
endfunction
call t#it('keeps the cursor at the end and drops the oldest lines', function('s:test_follow_end'))
