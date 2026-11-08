" End-to-end tests against a kind cluster, see `make test-e2e`: skipped when
" $KUBE_E2E_CONTEXT is not set or its cluster is not reachable.
let s:CONTEXT = $KUBE_E2E_CONTEXT
let s:NS = 'kube-e2e'
let s:TIMEOUT = 60000
let s:CHART = fnamemodify(expand('<sfile>:p'), ':h') . '/chart'

" Run {cmd} synchronously: [code, stdout].
function! s:run(cmd, ...) abort
  let out = system(join(map(copy(a:cmd), 'shellescape(v:val)')), get(a:, 1, ''))
  return [v:shell_error, out]
endfunction

" kubectl in the test namespace.
function! s:k(args, ...) abort
  return call('s:run', [['kubectl', '--context', s:CONTEXT, '-n', s:NS] + a:args] + a:000)
endfunction

function! s:jsonpath(args) abort
  return trim(s:k(a:args)[1])
endfunction

" helm in the test namespace.
function! s:h(args) abort
  return s:run(['helm', '--kube-context', s:CONTEXT, '-n', s:NS] + a:args)
endfunction

let s:reachable = !empty(s:CONTEXT) && s:run(['kubectl', '--context', s:CONTEXT, '--request-timeout=10s', 'version'])[0] == 0
let s:setup_errors = []
function! s:setup(result, what) abort
  if a:result[0] != 0
    call add(s:setup_errors, a:what . ': ' . trim(a:result[1]))
  endif
endfunction
if s:reachable
  call kube#kubectl#set_context(s:CONTEXT)
  " Reset what the tests change, so that they can be rerun on the same cluster
  call s:setup(s:k(['scale', 'deployment/web', '--replicas=1']), 'scale web')
  call s:setup(s:k(['rollout', 'status', 'deployment/web', '--timeout=120s']), 'roll out web')
  call s:setup(s:k(['replace', '-f', '-'], json_encode({
        \ 'apiVersion': 'v1',
        \ 'kind': 'Secret',
        \ 'metadata': {'name': 'db', 'namespace': s:NS},
        \ 'stringData': {'username': 'admin', 'password': 's3cret'},
        \ })), 'reset the secret db')
  " A release with two revisions
  call s:setup(s:h(['uninstall', 'greeter', '--ignore-not-found', '--wait']), 'uninstall greeter')
  call s:setup(s:h(['install', 'greeter', s:CHART]), 'install greeter')
  call s:setup(s:h(['upgrade', 'greeter', s:CHART, '--set', 'greeting=hi']), 'upgrade greeter')
endif

function! s:before() abort
  if !s:reachable
    call t#skip(empty(s:CONTEXT) ? 'KUBE_E2E_CONTEXT is not set' : 'the cluster of ' . s:CONTEXT . ' is not reachable')
  endif
  if !empty(s:setup_errors)
    throw join(s:setup_errors, "\n")
  endif
endfunction
call t#before_each(function('s:before'))

function! s:after() abort
  call t#restore_stubs()
  call t#clean_buffers()
  call kube#portforward#stop_all()
endfunction
call t#after_each(function('s:after'))

function! s:list(kind) abort
  return printf('kube://context/%s/namespaces/%s/%s', s:CONTEXT, s:NS, a:kind)
endfunction

function! s:open(name) abort
  call t#open(a:name, s:TIMEOUT)
endfunction

" Wait for a line matching {pattern}, returns it.
function! s:wait_line(pattern) abort
  call t#wait_for({-> !empty(s:line_matching(a:pattern))}, 'a line matching ' . a:pattern . ' in ' . bufname(''), s:TIMEOUT)
  return s:line_matching(a:pattern)
endfunction

function! s:line_matching(pattern) abort
  return get(filter(t#lines(), 'v:val =~# a:pattern'), 0, '')
endfunction

call t#describe('kind cluster')

function! s:test_pods() abort
  call s:open(s:list('pods'))
  call s:wait_line('^kube-e2e\s\+web-.\{-}Running')
  call s:wait_line('^kube-e2e\s\+logger-.\{-}Running')
endfunction
call t#it('lists pods', function('s:test_pods'))

function! s:test_describe() abort
  call s:open(s:list('pods'))
  call t#press_on('web-', 'K')
  call t#wait_for({-> !empty(filter(kube#compat#floats(), 'join(v:val[1], "\n") =~# "Namespace:\\s\\+kube-e2e"'))}, 'describe', s:TIMEOUT)
endfunction
call t#it('describes in a float', function('s:test_describe'))

function! s:test_logs() abort
  call s:open(s:list('pods'))
  call t#press_on('logger-', 'gl')
  call s:wait_line('^log-line-\d\+$')

  call s:open(s:list('pods'))
  call t#press_on('logger-', 'gL')
  call s:wait_line('^log-line-\d\+$')
  let lines = line('$')
  call t#wait_for({-> line('$') > lines}, 'new log lines', s:TIMEOUT)
  call t#press("\<C-c>")
endfunction
call t#it('shows and follows logs', function('s:test_logs'))

function! s:diff_and_yes(items, opts) abort
  for win in range(1, winnr('$'))
    if getbufvar(winbufnr(win), '&filetype') ==# 'diff'
      let g:t_diff = join(getbufline(winbufnr(win), 1, '$'), "\n")
    endif
  endfor
  return 'Yes'
endfunction

function! s:test_apply() abort
  call s:open(s:list('deployments'))
  call t#press_on('web', 'gd')
  call t#wait_loaded(s:TIMEOUT)
  let lnum = search('^  replicas: 1$', 'cw')
  call assert_true(lnum > 0, 'spec.replicas')
  call setline(lnum, '  replicas: 2')
  let g:t_diff = ''
  call t#answer_prompts(function('s:diff_and_yes'), v:null)
  write
  call t#wait_for({-> s:jsonpath(['get', 'deployment', 'web', '-o', 'jsonpath={.spec.replicas}']) ==# '2'}, 'replicas to be 2', s:TIMEOUT)
  call assert_match('+  replicas: 2', g:t_diff)
endfunction
call t#it('applies edited YAML after showing the diff', function('s:test_apply'))

function! s:test_scale_restart() abort
  call s:open(s:list('deployments'))
  call t#answer_prompts(v:null, '1')
  call t#press_on('web', '')
  call t#operation('Scale…')
  call t#wait_for({-> s:jsonpath(['get', 'deployment', 'web', '-o', 'jsonpath={.spec.replicas}']) ==# '1'}, 'replicas to be 1', s:TIMEOUT)

  call t#answer_yes()
  call t#press_on('web', '')
  call t#operation('Restart')
  let annotation = 'jsonpath={.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}'
  call t#wait_for({-> !empty(s:jsonpath(['get', 'deployment', 'web', '-o', annotation]))}, 'restart annotation', s:TIMEOUT)
  call assert_equal(0, s:k(['rollout', 'status', 'deployment/web', '--timeout=120s'])[0], 'rollout after restart')
endfunction
call t#it('scales and restarts with operations', function('s:test_scale_restart'))

function! s:test_scale_cell() abort
  call s:open(s:list('deployments'))
  call t#answer_yes()
  let kbuf = t#kbuf()
  let cells = kube#compat#cells(kbuf.bufnr)
  for [id, cell] in items(kbuf.cells)
    if cell.column ==# 'DESIRED' && cell.item.metadata.name ==# 'web'
      call cursor(cells[id][0], cells[id][1] + 1)
    endif
  endfor
  call t#press("ciw2\<Esc>")
  write
  call t#wait_for({-> s:jsonpath(['get', 'deployment', 'web', '-o', 'jsonpath={.spec.replicas}']) ==# '2'}, 'replicas to be 2', s:TIMEOUT)
endfunction
call t#it('scales by editing the DESIRED cell', function('s:test_scale_cell'))

function! s:test_secrets() abort
  call s:open(s:list('secrets'))
  call t#press_on('db', "\<CR>")
  call t#wait_loaded(s:TIMEOUT)
  call s:wait_line('^username: "admin"$')
  call s:wait_line('^password: "s3cret"$')
  call setline(search('^username: "admin"$', 'cw'), 'username: "root"')
  call t#answer_yes()
  write
  call t#wait_for({-> s:jsonpath(['get', 'secret', 'db', '-o', 'jsonpath={.data.username}']) ==# 'cm9vdA=='}, 'username to be root', s:TIMEOUT)
endfunction
call t#it('decodes and updates secrets', function('s:test_secrets'))

function! s:test_events() abort
  call s:open(s:list('events'))
  call s:wait_line('^kube-e2e\s\+')
endfunction
call t#it('lists events', function('s:test_events'))

function! s:test_related_events() abort
  call s:open(s:list('deployments'))
  call t#press_on('web', '')
  call t#operation('Show events')
  " The restart above created pods, whose events belong to the deployment's
  call s:wait_line('Scheduled\s\+pod/web-')
endfunction
call t#it('shows the events of a deployment and its pods', function('s:test_related_events'))

function! s:test_forward() abort
  call s:open(s:list('services'))
  let g:t_asked = 0
  call t#answer_prompts({items, opts -> g:t_asked ? v:null : [execute('let g:t_asked = 1'), items[0]][1]}, '18080')
  call t#press_on('web', 'gf')
  call t#wait_for({-> s:run(['curl', '-s', 'http://localhost:18080'])[1] =~# 'nginx'}, 'nginx through the port forward', s:TIMEOUT)
endfunction
call t#it('forwards ports', function('s:test_forward'))

function! s:test_exec() abort
  call s:open(s:list('pods'))
  " Not a pod still terminating after the restart
  let pod = matchstr(s:wait_line('^kube-e2e\s\+web-\S\+\s\+1/1\s\+Running'), '^kube-e2e\s\+\zs\S\+')
  call t#press_on(pod, 'gs')
  if has('nvim')
    stopinsert
    call chansend(&channel, "echo e2e-$((40+2))\n")
  else
    call term_sendkeys(bufnr(''), "echo e2e-$((40+2))\n")
  endif
  call t#wait_for({-> join(t#lines(), "\n") =~# 'e2e-42'}, 'exec output', s:TIMEOUT)
endfunction
call t#it('execs into a container', function('s:test_exec'))

function! s:test_delete_line() abort
  call s:open(s:list('pods'))
  let pod = matchstr(s:wait_line('^kube-e2e\s\+logger-'), '^kube-e2e\s\+\zs\S\+')
  call t#answer_yes()
  call t#press_on(pod, 'dd')
  write
  call t#wait_for({-> s:k(['get', 'pod', pod])[0] != 0}, 'pod ' . pod . ' to be deleted', s:TIMEOUT * 2)
endfunction
call t#it('deletes a pod by deleting its line', function('s:test_delete_line'))

call t#describe('helm releases')

function! s:test_releases() abort
  let release = s:list('helm-releases') . '/greeter'
  call s:open(s:list('helm-releases'))
  call s:wait_line('^kube-e2e\s\+greeter\s\+2\s\+deployed\s\+kube-e2e-0\.1\.0\s\+1\.0')
  call t#press_on('greeter', "\<CR>")
  call s:wait_line('greeting: "hi"')
  call assert_equal(release . '/manifest', bufname(''))

  call s:open(s:list('helm-releases'))
  call t#press_on('greeter', 'gd')
  call s:wait_line('^greeting: hi$')
endfunction
call t#it('lists releases, <CR> shows the manifest, gd the values', function('s:test_releases'))

function! s:test_rollback() abort
  call s:open(s:list('helm-releases') . '/greeter/history')
  call s:wait_line('^2\s.\{-}deployed')
  call t#answer_yes()
  call t#press_on('Install complete', '')
  call t#operation('Rollback to revision 1')
  call t#wait_for({-> get(get(json_decode(s:h(['history', 'greeter', '-o', 'json'])[1]), 2, {}), 'description', '') ==# 'Rollback to 1'},
        \ 'revision 3 rolling back to 1', s:TIMEOUT)
endfunction
call t#it('rolls back to a revision of the history', function('s:test_rollback'))

function! s:test_uninstall() abort
  call s:open(s:list('helm-releases'))
  call s:wait_line('greeter')
  call t#answer_yes()
  call t#press_on('greeter', 'dd')
  write
  call t#wait_for({-> s:h(['status', 'greeter'])[0] != 0}, 'release greeter to be uninstalled', s:TIMEOUT)
endfunction
call t#it('uninstalls a release by deleting its line', function('s:test_uninstall'))
