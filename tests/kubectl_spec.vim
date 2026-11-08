" Run the async kubectl function {name} with {args} and wait for its callback:
" returns {result, errors}.
function! s:run(name, ...) abort
  let state = {'done': 0, 'result': v:null, 'errors': []}
  call call('kube#kubectl#' . a:name, a:000 + [
        \ {data -> extend(state, {'result': data, 'done': 1})},
        \ {err -> add(state.errors, err)}])
  call t#wait_for({-> state.done}, 'kubectl callback')
  return state
endfunction

function! s:before() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
endfunction
call t#before_each(function('s:before'))

call t#describe('kubectl argument building')

function! s:respond_ok() abort
  call t#respond('*', {'stdout': 'ok'})
endfunction
call t#before_each(function('s:respond_ok'))

function! s:test_get_all() abort
  call s:run('get', 'ctx', 'pods', '', 'all', {'selector': 'app=web,tier=fe'})
  call assert_equal(['--context ctx get pods -o json --all-namespaces --selector=app=web,tier=fe'], t#calls())
endfunction
call t#it('get lists across all namespaces', function('s:test_get_all'))

function! s:test_get_named() abort
  call s:run('get', 'ctx', 'pod', 'web-1', 'ns1', {})
  call assert_equal(['--context ctx get pod -o json web-1 -n ns1'], t#calls())
endfunction
call t#it('get a named resource in a namespace', function('s:test_get_named'))

function! s:test_describe() abort
  call s:run('describe', 'ctx', 'deployment.apps', 'web', 'ns1')
  call assert_equal(['--context ctx describe deployment.apps web -n ns1'], t#calls())
endfunction
call t#it('describe', function('s:test_describe'))

function! s:test_cluster_scoped() abort
  call s:run('describe', 'ctx', 'node', 'n1', 'all')
  call s:run('get_resource_yaml', 'ctx', 'Node', 'n1', '')
  call assert_equal(['--context ctx describe node n1', '--context ctx get node n1 -o yaml'], t#calls())
endfunction
call t#it('omits -n for cluster-scoped resources', function('s:test_cluster_scoped'))

function! s:test_delete() abort
  call s:run('delete', 'ctx', 'gateway.networking.istio.io', 'gw', 'istio-system')
  call assert_equal(['--context ctx delete gateway.networking.istio.io gw -n istio-system'], t#calls())
endfunction
call t#it('delete', function('s:test_delete'))

function! s:test_apply() abort
  call s:run('apply', 'ctx', 'ns1', '/tmp/x.yaml')
  call assert_equal(['--context ctx -n ns1 apply -f /tmp/x.yaml'], t#calls())
endfunction
call t#it('apply', function('s:test_apply'))

function! s:test_set_image() abort
  call s:run('set_image', 'ctx', 'deployment.apps', 'web', 'ns1', 'app', 'web:2')
  call assert_equal(['--context ctx set image deployment.apps/web app=web:2 -n ns1'], t#calls())
endfunction
call t#it('set image', function('s:test_set_image'))

function! s:test_port_forward() abort
  call s:run('forward_port', 'ctx', 'pod', 'web-1', 'ns1', 8080, 18080)
  call assert_equal(['--context ctx port-forward pod/web-1 18080:8080 -n ns1'], t#calls())
endfunction
call t#it('port-forward', function('s:test_port_forward'))

function! s:test_no_context() abort
  call s:run('get', v:null, 'pods', '', 'all', {})
  call assert_equal(['get pods -o json --all-namespaces'], t#calls())
endfunction
call t#it('without a context uses the kubeconfig current-context', function('s:test_no_context'))

function! s:test_operations() abort
  call s:run('scale', 'ctx', 'deployment.apps', 'web', 'ns1', 3)
  call s:run('rollout', 'ctx', 'restart', 'statefulset.apps', 'db', 'ns1')
  call s:run('node', 'ctx', 'cordon', 'node-1')
  call s:run('node', 'ctx', 'drain', 'node-1')
  call s:run('patch', 'ctx', 'secret', 'db', 'ns1', {'data': {'a': v:null}})
  call assert_equal([
        \ '--context ctx scale deployment.apps/web --replicas=3 -n ns1',
        \ '--context ctx rollout restart statefulset.apps/db -n ns1',
        \ '--context ctx cordon node-1',
        \ '--context ctx drain node-1 --ignore-daemonsets --delete-emptydir-data',
        \ ], t#calls()[0:3])
  " Neovim's json_encode() puts spaces after the separators
  let patch = matchlist(t#calls()[4], '^--context ctx patch secret db --type=merge -p \(.*\) -n ns1$')
  call assert_equal({'data': {'a': v:null}}, json_decode(patch[1]))
endfunction
call t#it('scale, rollout, node operations and patch', function('s:test_operations'))

function! s:test_request_timeout() abort
  call s:run('get', 'ctx', 'pods', '', 'ns1', {})
  call s:run('forward_port', 'ctx', 'pod', 'web-1', 'ns1', 8080, 18080)
  call s:run('node', 'ctx', 'drain', 'node-1')
  let raw = t#calls(1)
  call assert_match('--request-timeout=30s', raw[0])
  call assert_notmatch('--request-timeout', raw[1])
  call assert_notmatch('--request-timeout', raw[2])
endfunction
call t#it('sets a request timeout except for streams', function('s:test_request_timeout'))

function! s:test_spaces() abort
  call s:run('get', 'my ctx', 'pods', '', 'ns1', {'selector': 'env in (a, b)'})
  call assert_equal(1, len(t#calls_matching('^--context my ctx get pods -o json -n ns1 --selector=env in (a, b)$')))
endfunction
call t#it('keeps arguments with spaces intact', function('s:test_spaces'))

call t#describe('kubectl exec_cmd')

function! s:test_exec_container() abort
  call assert_equal(['kubectl', '--context', 'ctx', 'exec', '-it', 'pod/web-1', '-n', 'ns1', '-c', 'app',
        \ '--', 'sh', '-c', 'command -v bash >/dev/null && exec bash || exec sh'],
        \ kube#kubectl#exec_cmd('ctx', 'Pod', 'web-1', 'ns1', 'app'))
endfunction
call t#it('puts the container before the command', function('s:test_exec_container'))

function! s:test_exec_no_container() abort
  let cmd = kube#kubectl#exec_cmd('ctx', 'service', 'web', 'ns1', '')
  call assert_equal(['--', 'sh', '-c'], cmd[8:10])
  call assert_equal('service/web', cmd[5])
endfunction
call t#it('omits the container when not given', function('s:test_exec_no_container'))

call t#describe('kubectl results')

function! s:test_stdout() abort
  call t#respond('*describe*', {'stdout': "Name: web\n"})
  let out = s:run('describe', 'ctx', 'pod', 'web', 'ns1')
  call assert_equal("Name: web\n", out.result)
  call assert_equal([], out.errors)
endfunction
call t#it('passes stdout on success', function('s:test_stdout'))

function! s:test_stderr() abort
  call t#respond('*delete*', {'stderr': 'Error from server (NotFound)', 'code': 1})
  let out = s:run('delete', 'ctx', 'pod', 'web', 'ns1')
  call assert_equal(v:null, out.result)
  call assert_equal(['Error from server (NotFound)'], out.errors)
endfunction
call t#it('passes stderr to the error callback and v:null to the callback on failure', function('s:test_stderr'))

function! s:test_warnings() abort
  call t#respond('*apply*', {'stdout': 'configured', 'stderr': 'Warning: deprecated'})
  let out = s:run('apply', 'ctx', 'ns1', '/tmp/x.yaml')
  call assert_equal('configured', out.result)
  call assert_equal([], out.errors)
endfunction
call t#it('ignores warnings on stderr when the command succeeds', function('s:test_warnings'))

function! s:test_diff_codes() abort
  call t#respond('*diff*', {'stdout': "-a\n+b\n", 'code': 1})
  call assert_equal("-a\n+b\n", s:run('diff', 'ctx', 'ns1', '/tmp/x.yaml').result)
  call t#respond('*diff*', {'stdout': '', 'code': 0})
  call assert_equal('', s:run('diff', 'ctx', 'ns1', '/tmp/x.yaml').result)
  call t#respond('*diff*', {'stderr': 'error: invalid object', 'code': 2})
  let out = s:run('diff', 'ctx', 'ns1', '/tmp/x.yaml')
  call assert_equal(v:null, out.result)
  call assert_equal(['error: invalid object'], out.errors)
endfunction
call t#it('diff treats exit code 1 (differences) as success', function('s:test_diff_codes'))

call t#describe('kubectl logs')

function! s:logs(opts, ...) abort
  let state = {'chunks': []}
  let job = call('kube#kubectl#logs', (a:0 ? a:000 : ['ctx', 'pod', 'web-1', 'ns1']) + [a:opts, {data -> add(state.chunks, data)}])
  let state.job = job
  return state
endfunction

function! s:test_logs_whole() abort
  call t#respond('*logs*', {'stdout': "line1\nline2\n"})
  let state = s:logs({'container': 'app'})
  call t#wait_for({-> !empty(state.chunks)}, 'logs')
  call assert_equal(["line1\nline2"], state.chunks)
  call assert_equal(['--context ctx logs pod/web-1 -c app -n ns1 --tail=1000'], t#calls())
endfunction
call t#it('returns the whole output without the trailing newline', function('s:test_logs_whole'))

function! s:test_logs_options() abort
  call t#respond('*logs*', {'stdout': 'x'})
  let state = s:logs({'previous': 1, 'all_containers': 1, 'since': '1h', 'tail': -1}, 'ctx', 'deployment.apps', 'web', 'ns1')
  call t#wait_for({-> !empty(state.chunks)}, 'logs')
  call assert_equal(['--context ctx logs deployment.apps/web -n ns1 --tail=-1 --previous --all-containers --since=1h'], t#calls())
endfunction
call t#it('passes previous, all containers, since and tail', function('s:test_logs_options'))

function! s:test_logs_errors() abort
  call t#respond('*logs*', {'stderr': 'container not found', 'code': 1})
  let state = s:logs({})
  call t#wait_for({-> !empty(state.chunks)}, 'logs')
  call assert_equal(['container not found'], state.chunks)
endfunction
call t#it('shows errors in place of the logs', function('s:test_logs_errors'))

function! s:test_logs_stream() abort
  call t#respond('*logs*', {'script': "printf 'a\\nb'; sleep 0.2; printf 'c\\nd\\n'"})
  let state = s:logs({'follow': 1})
  call t#wait_for({-> !kube#compat#running(state.job) && len(state.chunks) == 2}, 'log chunks')
  call assert_equal(['a', "bc\nd"], state.chunks)
  call assert_equal(['--context ctx logs pod/web-1 -n ns1 --tail=1000 -f'], t#calls())
endfunction
call t#it('streams complete lines when following', function('s:test_logs_stream'))

function! s:test_logs_flush() abort
  call t#respond('*logs*', {'script': "printf 'a\\nb'"})
  let state = s:logs({'follow': 1})
  call t#wait_for({-> len(state.chunks) == 2}, 'log chunks')
  call assert_equal(['a', 'b'], state.chunks)
endfunction
call t#it('flushes a final partial line when the stream ends', function('s:test_logs_flush'))

call t#describe('kubectl kill')

function! s:test_kill() abort
  call t#respond('*', {'script': 'sleep 30'})
  let job = kube#kubectl#describe('ctx', 'pod', 'web', 'ns1', {data -> 0}, v:null)
  call kube#compat#kill(job)
  call t#wait_for({-> !kube#compat#running(job)}, 'job to exit')
  call kube#compat#kill(job)
  call kube#compat#kill({})
endfunction
call t#it('kills running jobs and ignores finished ones', function('s:test_kill'))

call t#describe('kubectl contexts')

function! s:test_prefers_switched() abort
  call t#respond('*current-context*', {'stdout': "from-kubeconfig\n"})
  call assert_equal('from-kubeconfig', kube#kubectl#get_current_context())
  call kube#kubectl#set_context('local')
  call assert_equal('local', kube#kubectl#get_current_context())
endfunction
call t#it('prefers the context switched to in the editor', function('s:test_prefers_switched'))

function! s:test_no_cache() abort
  call t#respond('*current-context*', {'stdout': "a\n"})
  call assert_equal('a', kube#kubectl#get_current_context())
  call t#respond('*current-context*', {'stdout': "b\n"})
  call assert_equal('b', kube#kubectl#get_current_context())
endfunction
call t#it('does not cache the kubeconfig current-context', function('s:test_no_cache'))

function! s:test_no_current() abort
  call t#respond('*current-context*', {'stderr': 'error: current-context is not set', 'code': 1})
  call assert_equal('', kube#kubectl#get_current_context())
endfunction
call t#it('returns nothing without a current-context', function('s:test_no_current'))

function! s:test_context_names() abort
  call t#respond('*get-contexts*', {'stdout': "a\nb\n"})
  call assert_equal(['a', 'b'], kube#kubectl#context_names_sync())
endfunction
call t#it('lists context names', function('s:test_context_names'))

function! s:test_persists() abort
  call kube#kubectl#use_context('saved-ctx', {result -> 0})
  call kube#kubectl#set_context(v:null)
  runtime autoload/kube/kubectl.vim
  call assert_equal('saved-ctx', kube#kubectl#context())
endfunction
call t#it('persists the switched context', function('s:test_persists'))

function! s:test_corrupt_state() abort
  call writefile(['{not json'], kube#compat#state_file('kube_state.json'))
  call kube#kubectl#set_context(v:null)
  runtime autoload/kube/kubectl.vim
  call assert_equal(v:null, kube#kubectl#context())
endfunction
call t#it('ignores a corrupt state file', function('s:test_corrupt_state'))

call t#describe('kubectl api_resources_sync')

function! s:test_api_resources_cache() abort
  call t#respond('*api-resources*', {'stderr': 'unreachable', 'code': 1})
  call assert_equal([], kube#kubectl#api_resources_sync())
  call t#respond('*api-resources*', {'stdout': "pods\ndeployments.apps\n"})
  call assert_equal(['pods', 'deployments.apps'], kube#kubectl#api_resources_sync())
  call assert_equal(['pods', 'deployments.apps'], kube#kubectl#api_resources_sync())
  call assert_equal(2, len(t#calls_matching('api-resources')))

  call kube#kubectl#set_context('other')
  call kube#kubectl#api_resources_sync()
  call assert_equal(1, len(t#calls_matching('^--context other api-resources')))
endfunction
call t#it('caches per context and does not cache failures', function('s:test_api_resources_cache'))
