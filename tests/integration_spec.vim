let s:PODS = 'kube://context/ctx-a/namespaces/ns1/pods'

function! s:before() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
  call t#respond('*get pods -o json*', {'fixture': 'pods.json'})
  call t#respond('*get pod -o json web-1 *', {'fixture': 'pod-web-1.json'})
  call t#respond('*get deployments -o json*', {'fixture': 'deployments.json'})
  call t#respond('*get deployment.apps web -o yaml*', {'fixture': 'deployment-web.yaml'})
  call t#respond('*describe*', {'stdout': 'Name: web'})
  call t#respond('*logs*', {'stdout': "line1\nline2\n"})
  call t#capture_notify()
endfunction
call t#before_each(function('s:before'))

function! s:after() abort
  call t#restore_stubs()
  call t#clean_buffers()
  call kube#portforward#stop_all()
endfunction
call t#after_each(function('s:after'))

call t#describe('opening buffers')

function! s:test_get() abort
  Kube get pods namespace=ns1 selector=app=web
  call t#wait_loaded()
  call assert_equal(s:PODS . '?selector=app=web', bufname(''))
  call assert_equal(['--context ctx-a get pods -o json -n ns1 --selector=app=web'], t#calls_matching('get pods'))
  let lines = t#lines()
  call assert_equal(2, len(lines))
  call assert_match('^ns1\s\+web-1\s\+2/2\s\+Running', lines[0])
  call assert_match('^ns1\s\+web-2\s\+0/1\s\+Pending', lines[1])
  call assert_equal('acwrite', &buftype)
endfunction
call t#it(':Kube get pins the current context and renders the resources', function('s:test_get'))

function! s:test_diagnostics() abort
  call t#open('kube://pods')
  let diagnostics = t#diagnostics()
  call assert_equal(1, len(diagnostics))
  call assert_equal(2, diagnostics[0][0])
endfunction
call t#it('shows unhealthy resources as diagnostics', function('s:test_diagnostics'))

function! s:test_reuses_pinned() abort
  call t#open('kube://namespaces/ns1/pods')
  let first = bufnr('')
  enew
  edit kube://namespaces/ns1/pods
  call t#wait_for({-> bufnr('') == first}, 'switch to the existing buffer')
  call t#wait(50)
  call assert_equal(s:PODS, bufname(''))
  call assert_equal(1, len(t#calls_matching('get pods')))
  call assert_equal([], filter(getbufinfo(), 'v:val.name ==# "kube://namespaces/ns1/pods"'))
endfunction
call t#it('reuses the pinned buffer when the shorthand is opened again', function('s:test_reuses_pinned'))

function! s:test_explicit_context() abort
  call t#open('kube://context/ctx-b/pods')
  call assert_equal(['--context ctx-b get pods -o json --all-namespaces'], t#calls_matching(' get '))
endfunction
call t#it('uses an explicit context without asking for the current one', function('s:test_explicit_context'))

function! s:test_encoded_context() abort
  call kube#kubectl#set_context('arn:aws:eks:r:1:cluster/prod')
  Kube get pods
  call t#wait_loaded()
  call assert_equal('kube://context/arn%3aaws%3aeks%3ar%3a1%3acluster%2fprod/pods', bufname(''))
  call assert_equal(1, len(t#calls_matching('^--context arn:aws:eks:r:1:cluster/prod get pods')))
endfunction
call t#it('encodes contexts with / and :', function('s:test_encoded_context'))

function! s:test_missing_context() abort
  let messages = t#capture_notify()
  call t#respond('*config current-context*', {'stderr': 'error: current-context is not set', 'code': 1})
  edit kube://pods
  call assert_equal('No current kubectl context', messages[0].msg)
  call assert_equal({}, resource#get(bufnr('')))
endfunction
call t#it('reports a missing current context', function('s:test_missing_context'))

call t#describe('context pinning')

function! s:test_pinned_after_switch() abort
  call t#open('kube://namespaces/ns1/pods')
  let pinned = bufnr('')
  Kube context ctx-b

  call t#press_on('web-1', 'R')
  call t#wait_loaded()
  call assert_equal(2, len(t#calls_matching('^--context ctx-a get pods')))
  call assert_equal(0, len(t#calls_matching('ctx-b')))

  call t#respond('*delete*', {'stdout': 'deleted'})
  call t#answer_prompts({items, opts -> 'Yes'}, v:null)
  call t#press_on('web-2', 'dd')
  write
  call t#wait_call('delete')
  call assert_equal(['--context ctx-a delete pod web-2 -n ns1'], t#calls_matching('delete'))

  Kube get pods namespace=ns1
  call t#wait_loaded()
  call assert_equal('kube://context/ctx-b/namespaces/ns1/pods', bufname(''))
  call assert_notequal(pinned, bufnr(''))
endfunction
call t#it("keeps operating on the buffer's context after switching", function('s:test_pinned_after_switch'))

function! s:test_no_alias_left() abort
  call t#open('kube://context/ctx-a/namespaces/ns1/deployments')
  let deployments = bufnr('')
  call t#open('kube://namespaces/ns1/pods')
  let pods = bufnr('')
  call assert_equal('kube://context/ctx-a/namespaces/ns1/pods', bufname(''))
  call assert_equal(deployments, bufnr('#'))

  edit kube://context/ctx-a/namespaces/ns1/deployments
  edit kube://namespaces/ns1/pods
  call assert_equal(pods, bufnr(''), 'the existing pinned buffer')
  call assert_equal(deployments, bufnr('#'))
  call t#wait(20)
  call assert_equal([], filter(getbufinfo(), 'v:val.name ==# "kube://namespaces/ns1/pods"'), 'the alias is wiped')

  execute "normal! \<C-o>"
  call assert_equal(deployments, bufnr(''), '<C-o> goes back')
endfunction
call t#it('edits the pinned buffer for a name without context, leaving no alias behind', function('s:test_no_alias_left'))

call t#describe('ns')

function! s:test_ns() abort
  call t#open('kube://namespaces/ns1/pods')
  let pods = bufnr('')
  call t#open('kube://ns/ns1/deployments')
  call assert_equal('kube://context/ctx-a/namespaces/ns1/deployments', bufname(''))
  edit kube://context/ctx-a/ns/ns1/pods
  call assert_equal(pods, bufnr(''))
endfunction
call t#it('opens the same buffer as namespaces', function('s:test_ns'))

call t#describe('resource under the cursor')

function! s:test_latest_render() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#respond('*get pods -o json*', {'fixture': 'pods-reversed.json'})
  call t#press_on('web-1', 'R')
  call t#wait_loaded()
  call assert_match('web-2', getline(1), 'list is reordered')
  call cursor(1, stridx(getline(1), 'web-2') + 1)
  call t#press('gd')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-2?output=yaml')
endfunction
call t#it('follows the latest render after a refresh', function('s:test_latest_render'))

function! s:test_keeps_cursor() abort
  call t#open('kube://namespaces/ns1/pods')
  call cursor(2, 8)
  call t#respond('*get pods -o json*', {'fixture': 'pods-reversed.json'})
  call t#press('R')
  call t#wait_loaded()
  call assert_match('web-2', getline(1), 'list is reordered')
  call assert_equal([1, 8], [line('.'), col('.')])
endfunction
call t#it('keeps the cursor on the same resource when reloading', function('s:test_keeps_cursor'))

function! s:test_cursor_gone() abort
  call t#open('kube://namespaces/ns1/pods')
  call cursor(2, 1)
  let only_web_1 = t#json('pods.json')
  let only_web_1.items = only_web_1.items[0:0]
  call t#respond('*get pods -o json*', {'stdout': json_encode(only_web_1)})
  call t#press('R')
  call t#wait_loaded()
  call assert_equal(1, line('$'))
  call assert_equal(1, line('.'))
endfunction
call t#it('keeps the cursor line when its resource is gone', function('s:test_cursor_gone'))

function! s:test_line_without_resource() abort
  call t#open('kube://namespaces/ns1/pods')
  normal! Go
  call t#press("\<Esc>K")
  call assert_equal(s:PODS, bufname(''))
  call assert_equal([], resource#compat#floats())
endfunction
call t#it('ignores lines without a resource', function('s:test_line_without_resource'))

call t#describe('actions')

function! s:test_containers() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', "\<CR>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/containers')
  call t#wait_loaded()
  call assert_equal(1, len(t#calls_matching('^--context ctx-a get pod -o json web-1 -n ns1$')))
  call assert_match('^init\s\+init\s\+Completed\s\+0\s\+busybox:1', getline(1))
  call assert_match('^app\s\+main\s\+Running\s\+1\s\+web:1\s\+8080/TCP, 9090/TCP', getline(2))
  call assert_match('^sidecar', getline(3))
endfunction
call t#it('drills down from a pod to its containers', function('s:test_containers'))

function! s:test_deployment_pods() abort
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', "\<CR>")
  call t#wait_buf_name(s:PODS . '?selector=app=web,tier=frontend')
  call t#wait_loaded()
  call assert_equal(1, len(t#calls_matching('get pods .*--selector=app=web,tier=frontend$')))
endfunction
call t#it('drills down from a deployment to its pods', function('s:test_deployment_pods'))

function! s:test_describe() abort
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'K')
  let float = t#wait_float('Name: web')
  call assert_equal(['--context ctx-a describe deployment.apps web -n ns1'], t#calls_matching('describe'))
  call resource#compat#close_float(float)
endfunction
call t#it('K describes in a float with the group-qualified type', function('s:test_describe'))

function! s:test_yaml() abort
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'gd')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call t#wait_loaded()
  call assert_equal('kind: Deployment', getline(2))
  call assert_equal('yaml', &filetype)
  call assert_equal(1, &modifiable)

  " Nothing to apply without changes
  write
  call t#wait(100)
  call assert_equal([], t#calls_matching('apply'))
endfunction
call t#it('goes to the editable YAML definition', function('s:test_yaml'))

function! s:test_yaml_read_only() abort
  call t#respond('*get deployment.apps web -o yaml*', {'stderr': 'forbidden', 'code': 1})
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'gd')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call t#wait_loaded()
  call assert_equal([''], t#lines())
  call assert_equal(0, &modifiable)
  call assert_equal('✗ forbidden', t#status())
endfunction
call t#it('keeps the YAML read-only when it cannot be loaded', function('s:test_yaml_read_only'))

function! s:forward_first_port(local_port) abort
  let g:t_asked = 0
  call t#answer_prompts({items, opts -> g:t_asked ? v:null : [execute('let g:t_asked = 1'), items[0]][1]}, a:local_port)
endfunction

function! s:test_open_forward() abort
  call t#respond('*port-forward*', {'script': 'sleep 30'})
  call s:forward_first_port('18080')
  call t#capture_open()
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gf')
  call t#press_on('web-1', 'gF')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/portforward')
  call t#wait_loaded()
  call t#press_on('http://localhost:18080', '')
  call t#operation('Open in browser')
  call assert_equal(['http://localhost:18080'], g:t_opened)
endfunction
call t#it('opens port forward URLs', function('s:test_open_forward'))

function! s:test_logs() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gl')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs')
  call t#wait_for({-> getline(1) ==# 'line1'}, 'logs')
  call assert_equal(['line1', 'line2'], t#lines())
  call assert_equal(['--context ctx-a logs pod/web-1 -n ns1 --tail=1000'], t#calls_matching('logs'))
endfunction
call t#it('shows pod logs', function('s:test_logs'))

function! s:test_edit_logs() abort
  call t#respond('*logs*', {'stdout': "a\\tb\n"})
  call t#open('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs')
  call assert_equal(['a\tb'], t#lines())
  %s/\\t/\t/g
  call assert_equal(["a\tb"], t#lines())
  call t#fails('write', 'E382:')
  call assert_equal(["a\tb"], t#lines())
  call assert_equal(1, len(t#calls_matching('logs')))
  call assert_equal(0, &modified, 'edits do not block quitting')

  let file = tempname()
  execute 'write' file
  call assert_equal(["a\tb"], readfile(file))

  edit
  call t#wait_loaded()
  call assert_equal(['a\tb'], t#lines())
  call assert_equal(1, &modifiable)
endfunction
call t#it('logs can be edited, :w keeps the edits and :e reloads', function('s:test_edit_logs'))

function! s:open_containers() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', "\<CR>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/containers')
  call t#wait_loaded()
endfunction

function! s:test_container_logs() abort
  call s:open_containers()
  call t#press_on('sidecar', 'gl')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?container=sidecar')
  call t#wait_call('logs')
  call assert_equal(['--context ctx-a logs pod/web-1 -c sidecar -n ns1 --tail=1000'], t#calls_matching('logs'))
endfunction
call t#it('shows container logs', function('s:test_container_logs'))

function! s:test_follow_logs() abort
  call t#respond('*logs*', {'script': "printf 'a\\nb\\n'; sleep 30"})
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gL')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true')
  call t#wait_for({-> getline(1) ==# 'a'}, 'streamed logs')
  call assert_equal(['a', 'b', ''], t#lines())
  call assert_match('Waiting for new logs', t#status())

  let job = t#kbuf().follow_job
  call t#press("\<C-c>")
  call t#wait_for({-> !resource#running(job)}, 'logs job to stop')
  call assert_match('Stopped following logs', t#status())
endfunction
call t#it('follows logs and stops on <C-c>', function('s:test_follow_logs'))

function! s:test_exec_container() abort
  call t#respond('*exec*', {'script': 'sleep 30'})
  call s:open_containers()
  call t#press_on('app', 'gs')
  stopinsert
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/exec?container=app')
  call t#wait_call('exec -it')
  call assert_equal(['--context ctx-a exec -it pod/web-1 -n ns1 -c app -- sh -c command -v bash >/dev/null && exec bash || exec sh'],
        \ t#calls_matching('exec -it'))
endfunction
call t#it("execs into the selected container in the buffer's context", function('s:test_exec_container'))

function! s:test_reuses_shell() abort
  call t#respond('*exec*', {'script': 'sleep 30'})
  let name = 'kube://context/ctx-a/namespaces/ns1/pod/web-1/exec?container=app'
  call t#open('kube://namespaces/ns1/pods')
  let pods = bufnr('')
  execute 'edit' fnameescape(name)
  call t#wait_call('exec')
  call assert_equal(['--context ctx-a exec -it pod/web-1 -n ns1 -c app -- sh -c command -v bash >/dev/null && exec bash || exec sh'],
        \ t#calls_matching('exec -it'))
  call assert_equal('terminal', &buftype)
  call assert_equal(name, bufname(''))
  call assert_equal(pods, bufnr('#'))
  call t#wait(20)
  call assert_equal([name], map(filter(getbufinfo(), 'v:val.name =~# "exec"'), 'v:val.name'), 'a single shell buffer')
  call assert_equal([], filter(getbufinfo(), 'v:val.name =~# "^term://\\|^!"'), 'no term:// buffer left')
  let shell = bufnr('')

  call t#answer_prompts({items, opts -> items[0]}, v:null)
  call t#open('kube://ns/ns1/pods')
  call t#press_on('web-1', 'gs')
  stopinsert
  call assert_equal(shell, bufnr(''), 'the running shell')
  call assert_equal(1, len(t#calls_matching('exec -it')))
endfunction
call t#it('starts the shell from the buffer name, and reuses it', function('s:test_reuses_shell'))

function! s:test_exec_prompt() abort
  call t#respond('*exec*', {'script': 'sleep 30'})
  let g:t_offered = []
  call t#answer_prompts({items, opts -> [extend(g:t_offered, map(copy(items), 'opts.format_item(v:val)')), items[1]][1]}, v:null)
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gs')
  stopinsert
  call assert_equal(['app', 'sidecar'], g:t_offered)
  call t#wait_call('exec -it')
  call assert_match(' -c sidecar ', t#calls_matching('exec -it')[0])
endfunction
call t#it('prompts for the container to exec into', function('s:test_exec_prompt'))

function! s:test_set_image() abort
  call t#respond('*set image*', {'stdout': 'updated'})
  let g:t_asked = 0
  call t#answer_prompts({items, opts -> [execute('let g:t_asked += 1'), items[0]][1]}, 'web:2')
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'gi')
  call t#wait_call('set image')
  call assert_equal(['--context ctx-a set image deployment.apps/web app=web:2 -n ns1'], t#calls_matching('set image'))
  call t#wait_for({-> len(t#calls_matching('get deployments')) == 2}, 'reload')
  call assert_equal(1, g:t_asked)
endfunction
call t#it('sets the image and reloads', function('s:test_set_image'))

function! s:test_unsupported() abort
  let messages = t#capture_notify()
  call s:open_containers()
  call t#press_on('app', 'gi')
  call assert_equal({'msg': 'set_image is not supported for containers', 'level': 'warn'}, messages[-1])
endfunction
call t#it('warns about unsupported actions instead of failing', function('s:test_unsupported'))

function! s:test_help() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press('g?')
  let float = t#wait_float('Keymaps')
  let text = join(getbufline(winbufnr(float), 1, '$'), "\n")
  call assert_match('g?       show this help', text)
  call assert_match('K        describe the resource under the cursor', text)
  call assert_match('gra      all operations', text)
  call assert_match(':Kube get {kind}', text)
  if has('nvim')
    call assert_equal(float, win_getid(), 'help window is focused')
    call t#press('q')
  else
    call feedkeys('q', 'xt')
  endif
  call assert_equal([], resource#compat#floats())
endfunction
call t#it('shows the help with the configured keymaps', function('s:test_help'))

call t#describe('navigation')

function! s:before_navigation() abort
  call t#respond('*get namespaces -o json*', {'fixture': 'namespaces.json'})
  call t#respond('*api-resources*', {'fixture': 'api-resources.txt'})
  call t#respond('*get pod -o json --all-namespaces*', {'fixture': 'pods.json'})
  call t#respond('*get pod -o json -n ns1*', {'fixture': 'pods.json'})
  call t#respond('*get deployment.apps -o json -n ns1*', {'fixture': 'deployments.json'})
endfunction
call t#before_each(function('s:before_navigation'))

function! s:test_parents() abort
  call s:open_containers()
  for parent in [
        \ 'kube://context/ctx-a/namespaces/ns1/pod',
        \ 'kube://context/ctx-a/pod',
        \ 'kube://context/ctx-a/namespaces',
        \ 'kube://context/ctx-a/api-resources',
        \ ]
    call t#press('-')
    call t#wait_buf_name(parent)
    call t#wait_loaded()
  endfor
  call t#press('-')
  call assert_equal('kube://context/ctx-a/api-resources', bufname(''), 'the resource types have no parent')
endfunction
call t#it('- goes up to the parent until the namespaces', function('s:test_parents'))

function! s:test_resource_types() abort
  call t#open('kube://')
  call assert_equal('kube://context/ctx-a/api-resources', bufname(''))
  call assert_equal('bindings                 v1                      true        Binding   ', getline(1), 'empty SHORTNAMES')
  call assert_equal('deployments  deploy      apps/v1                 true        Deployment', getline(5))
  call t#press_on('deployments', "\<CR>")
  call t#wait_buf_name('kube://context/ctx-a/deployments.apps')
endfunction
call t#it('kube:// lists the resource types, which open their list', function('s:test_resource_types'))

function! s:test_namespaced_types() abort
  call t#open('kube://ns/ns1/api-resources')
  call t#press_on('deployments', "\<C-]>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployments.apps')
  execute "normal! \<C-t>"
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/api-resources')
  call t#press_on('nodes', 'gd')
  call t#wait_buf_name('kube://context/ctx-a/nodes')
endfunction
call t#it('opens namespaced resource types in the namespace of the list', function('s:test_namespaced_types'))

function! s:test_explain() abort
  call t#respond('*explain*', {'stdout': "GROUP:      apps\nKIND:       Deployment"})
  call t#open('kube://')
  call t#press_on('deployments', 'K')
  let float = t#wait_float('KIND:       Deployment')
  call assert_equal(['--context ctx-a explain deployments.apps'], t#calls_matching('explain'))
  call resource#compat#close_float(float)
endfunction
call t#it('K explains the resource type in a float', function('s:test_explain'))

function! s:test_partial_api_resources() abort
  let messages = t#capture_notify()
  let fixture = fnamemodify('tests/fixtures/api-resources.txt', ':p')
  call t#respond('*api-resources*', {'script': printf(
        \ "cat '%s'; echo 'error: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1' >&2; exit 1", fixture)})
  call t#open('kube://')
  call assert_match('deployments', join(t#lines(), "\n"))
  call assert_match('metrics.k8s.io', t#status())
  call assert_equal('error', messages[-1].level)
endfunction
call t#it('lists the resource types of the API groups that answer', function('s:test_partial_api_resources'))

function! s:test_parent_of_definition() abort
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'gd')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml')
  call t#wait_loaded()
  call t#press('-')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/deployment.apps')
  call t#wait_loaded()
  call assert_match('^ns1\s\+web\s\+1/2', getline(1))
endfunction
call t#it('- from a definition lists the kind with its formatter', function('s:test_parent_of_definition'))

function! s:test_parent_selector() abort
  call t#open('kube://namespaces/ns1/pods?selector=app=web')
  call t#press('-')
  call t#wait_buf_name('kube://context/ctx-a/pods?selector=app=web')
endfunction
call t#it('- keeps the selector when leaving the namespace', function('s:test_parent_selector'))

function! s:test_tag_namespace() abort
  call t#open('kube://pods?selector=app=web')
  let list = bufnr('')
  call t#press_on('ns1', "\<C-]>")
  call t#wait_buf_name(s:PODS . '?selector=app=web')
  call t#wait_loaded()
  call assert_equal(1, len(t#calls_matching('get pods -o json -n ns1 --selector=app=web$')))
  call t#press("\<C-t>")
  call assert_equal(list, bufnr(''))
endfunction
call t#it('<C-]> on a namespace filters the list, <C-t> goes back', function('s:test_tag_namespace'))

function! s:test_tag_node() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('node-1', "\<C-]>")
  call t#wait_buf_name('kube://context/ctx-a/node/node-1')
  call t#wait_call('describe')
  call assert_equal(['--context ctx-a describe node node-1'], t#calls_matching('describe'))
endfunction
call t#it('<C-]> on a node opens the node', function('s:test_tag_node'))

function! s:test_gd_like_tag() abort
  call t#open('kube://pods')
  call t#press_on('ns1', 'gd')
  call t#wait_buf_name(s:PODS)
endfunction
call t#it('gd jumps like <C-]>', function('s:test_gd_like_tag'))

function! s:test_tag_definition() abort
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('Running', "\<C-]>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml')
endfunction
call t#it('<C-]> elsewhere goes to the definition', function('s:test_tag_definition'))

function! s:test_tag_namespace_row() abort
  call t#open('kube://namespaces')
  call t#press_on('ns2', "\<C-]>")
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns2/pods')
endfunction
call t#it('<C-]> on a namespace row lists its pods', function('s:test_tag_namespace_row'))

function! s:test_tag_split() abort
  call t#open('kube://pods')
  call t#press_on('ns1', "\<C-w>]")
  call t#wait_buf_name(s:PODS)
  call assert_equal(2, winnr('$'))
  only
endfunction
call t#it('<C-w>] opens the jump in a split', function('s:test_tag_split'))

function! s:test_exact_columns() abort
  call t#open('kube://namespaces/ns1/pods')
  let kbuf = t#kbuf()
  let node_col = stridx(getline(1), 'node-1')
  let definition = 'kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml'
  let Target = {col -> kube#navigation#tag_target(kbuf, resource#cell(kbuf, 1, col))}
  call assert_equal('kube://context/ctx-a/node/node-1', Target(node_col), 'first char of NODE')
  call assert_equal('kube://context/ctx-a/node/node-1', Target(node_col + 5), 'last char of NODE')
  call assert_equal(definition, Target(node_col - 1), 'column separator')
  call assert_equal(definition, Target(node_col - 3), 'last char of IP')
endfunction
call t#it('<C-]> resolves cells by their exact columns', function('s:test_exact_columns'))

function! s:test_no_tag() abort
  call s:open_containers()
  call cursor(1, 1)
  call t#fails("execute \"normal \\<C-]>\"", 'E426:')
  call assert_equal('kube://context/ctx-a/namespaces/ns1/pod/web-1/containers', bufname(''))
endfunction
call t#it('<C-]> on a row without a resource reports no tag', function('s:test_no_tag'))

call t#describe('editing YAML')

let s:EDIT = 'kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml'

function! s:open_edit() abort
  call t#open('kube://namespaces/ns1/deployments')
  call t#press_on('web', 'gd')
  call t#wait_buf_name(s:EDIT)
  call t#wait_loaded()
  call assert_equal(1, &modifiable)
endfunction

function! s:before_yaml() abort
  call t#respond('*diff*', {'stdout': "-  replicas: 2\n+  replicas: 3\n", 'code': 1})
  call t#answer_prompts({items, opts -> 'Yes'}, v:null)
endfunction
call t#before_each(function('s:before_yaml'))

function! s:test_apply_once() abort
  call t#respond('*apply*', {'stdout': 'configured'})
  call s:open_edit()
  for _ in range(2)
    call t#press('R')
    call t#wait_loaded()
  endfor
  call setline(6, '  replicas: 3')
  write
  call t#wait_call('apply')
  call t#wait_for({-> len(t#calls_matching('-o yaml')) == 4}, 'reload after apply')
  call assert_equal(1, len(t#calls_matching('^--context ctx-a -n ns1 apply -f ')))
  call t#wait_for({-> !&modified}, 'reloaded buffer to be unmodified')
endfunction
call t#it('applies once per save, however often the buffer was refreshed', function('s:test_apply_once'))

function! s:test_apply_fails() abort
  let messages = t#capture_notify()
  call t#respond('*apply*', {'stderr': 'admission denied', 'code': 1})
  call s:open_edit()
  let buf = bufnr('')
  call setline(6, '  replicas: 3')
  write
  call t#wait_call('apply')
  call t#wait_for({-> !empty(messages) && messages[-1].msg =~# 'admission denied'}, 'error notification')
  call t#wait(50)
  call assert_true(bufexists(buf), 'buffer is kept')
  call assert_equal('  replicas: 3', getbufline(buf, 6)[0])
  call assert_equal(1, getbufvar(buf, '&modified'))
  call assert_equal(1, len(t#calls_matching('-o yaml')), 'not reloaded')
endfunction
call t#it('keeps the edits when apply fails', function('s:test_apply_fails'))

call t#describe('deleting by editing the list')

function! s:test_delete_all() abort
  call t#respond('*delete*', {'stdout': 'deleted'})
  let g:t_seen = []
  call t#answer_prompts({items, opts -> [add(g:t_seen, opts.prompt), 'Yes'][1]}, v:null)
  call t#open('kube://namespaces/ns1/pods')
  normal! ggdG
  write
  call t#wait_for({-> len(t#calls_matching('delete')) == 2 && len(t#calls_matching('get pods')) == 2}, 'deletes and reload')
  call assert_equal(['--context ctx-a delete pod web-1 -n ns1', '--context ctx-a delete pod web-2 -n ns1'], sort(t#calls_matching('delete')))
  call assert_equal(["Apply the changes (context: ctx-a)?\n  Delete pod: ns1/web-1\n  Delete pod: ns1/web-2"], g:t_seen)
endfunction
call t#it('deletes all deleted rows after one confirmation', function('s:test_delete_all'))

function! s:test_delete_cancelled() abort
  call t#answer_prompts({items, opts -> 'No'}, v:null)
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'dd')
  write
  call t#wait(100)
  call assert_equal([], t#calls_matching('delete'))
  call assert_equal(1, &modified)
endfunction
call t#it('deletes nothing when cancelled', function('s:test_delete_cancelled'))

call t#describe('port forwarding')

let s:KEY = 'ctx-a/ns1/pod/web-1'

" Forward the {choice}-th port of web-1 to {local_port}.
function! s:forward(choice, local_port) abort
  let g:t_asked = 0
  call t#answer_prompts({items, opts -> g:t_asked ? v:null : [execute('let g:t_asked = 1'), items[a:choice - 1]][1]}, string(a:local_port))
  call t#press_on('web-1', 'gf')
  call t#wait_for({-> has_key(get(kube#portforward#all(), s:KEY, {}), a:local_port)}, 'port forward ' . a:local_port)
endfunction

function! s:before_forwards() abort
  call t#respond('*port-forward*', {'script': 'sleep 30'})
endfunction
call t#before_each(function('s:before_forwards'))

function! s:test_forward() abort
  call t#open('kube://namespaces/ns1/pods')
  call s:forward(2, 19090)
  call t#wait_call('port-forward')
  call assert_equal(['--context ctx-a port-forward pod/web-1 19090:9090 -n ns1'], t#calls_matching('port-forward'))
  call assert_equal(9090, kube#portforward#all()[s:KEY][19090].container_port)
endfunction
call t#it("forwards the selected port in the buffer's context", function('s:test_forward'))

function! s:test_stop_deleted_forward() abort
  call t#open('kube://namespaces/ns1/pods')
  call s:forward(1, 18080)
  call s:forward(2, 19090)
  call t#wait_call('port-forward')
  let job_18080 = kube#portforward#all()[s:KEY][18080].job
  let job_19090 = kube#portforward#all()[s:KEY][19090].job

  call t#press_on('web-1', 'gF')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/portforward')
  call t#wait_loaded()
  call assert_equal(2, line('$'))
  call assert_match('http://localhost:18080', getline(1))

  call t#answer_prompts({items, opts -> 'Yes'}, v:null)
  call t#press_on('http://localhost:18080', 'dd')
  write
  call t#wait_for({-> !resource#running(job_18080)}, 'forward to stop')
  call t#wait_for({-> line('$') == 1 && getline(1) =~# 'http://localhost:19090'}, 'reload')
  call assert_false(has_key(kube#portforward#all()[s:KEY], 18080))
  call assert_true(has_key(kube#portforward#all()[s:KEY], 19090), 'other forward is kept')
  call assert_true(resource#running(job_19090))
endfunction
call t#it('lists forwards and stops only the deleted one', function('s:test_stop_deleted_forward'))

function! s:test_port_used() abort
  let messages = t#capture_notify()
  call t#open('kube://namespaces/ns1/pods')
  call s:forward(1, 18080)
  call t#wait_call('port-forward')
  call s:forward(1, 18080)
  call assert_equal(1, len(t#calls_matching('port-forward')))
  call assert_notequal(-1, index(map(copy(messages), 'v:val.msg'), 'Local port 18080 is already used'))
endfunction
call t#it('rejects a local port that is already forwarded', function('s:test_port_used'))

call t#describe('cleanup')

function! s:test_unloaded() abort
  call t#respond('*logs*', {'script': 'sleep 30'})
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gL')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true')
  let buf = bufnr('')
  let kbuf = t#kbuf()
  let job = kbuf.follow_job

  execute 'bunload!' buf
  call t#wait_for({-> !resource#running(job)}, 'job to stop')
  call assert_true(resource#get(buf) is kbuf, 'the state is kept')

  execute 'buffer' buf
  call assert_true(resource#running(kbuf.follow_job) && kbuf.follow_job isnot job, 'following again')
endfunction
call t#it('stops the jobs of an unloaded buffer and loads it again when edited', function('s:test_unloaded'))

function! s:test_wiped() abort
  call t#respond('*logs*', {'script': 'sleep 30'})
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gL')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true')
  let buf = bufnr('')
  let job = t#kbuf().follow_job
  execute 'bwipeout!' buf
  call t#wait_for({-> !resource#running(job)}, 'job to stop')
  call assert_equal({}, resource#get(buf))
endfunction
call t#it("stops the buffer's jobs when it is wiped", function('s:test_wiped'))

function! s:test_exit() abort
  call t#respond('*logs*', {'script': 'sleep 30'})
  call t#respond('*port-forward*', {'script': 'sleep 30'})
  call t#answer_prompts({items, opts -> items[0]}, '18080')
  call t#open('kube://namespaces/ns1/pods')
  call t#press_on('web-1', 'gf')
  call t#wait_for({-> has_key(get(kube#portforward#all(), s:KEY, {}), 18080)}, 'port forward')
  let forward_job = kube#portforward#all()[s:KEY][18080].job
  call t#restore_stubs()
  call t#capture_notify()

  call t#press_on('web-1', 'gL')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true')
  let logs_job = t#kbuf().follow_job

  doautocmd VimLeavePre
  call t#wait_for({-> !resource#running(logs_job) && !resource#running(forward_job)}, 'jobs to stop')
endfunction
call t#it('stops all jobs and port forwards on exit', function('s:test_exit'))
