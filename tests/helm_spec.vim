let s:RELEASES = 'kube://context/ctx-a/helm-releases'
let s:WEB = 'kube://context/ctx-a/namespaces/ns1/helm-releases/web'
" Every status, helm 3 and 4 list different ones by default
let s:LIST = 'helm --kube-context ctx-a list --deployed --failed --pending --superseded --uninstalled --uninstalling'

function! s:before() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
  call t#respond('helm *list * -o json*', {'fixture': 'helm-list.json'})
  call t#respond('helm *history web -o json*', {'fixture': 'helm-history.json'})
  call t#respond('helm *status web*', {'stdout': "NAME: web\nSTATUS: deployed\n"})
  call t#respond('helm *get values web -o yaml*', {'stdout': "replicas: 2\n"})
  call t#respond('helm *get manifest web*', {'stdout': "---\nkind: ConfigMap\n"})
  call t#respond('helm *get notes web*', {'stdout': "NOTES:\nThanks\n"})
  call t#capture_notify()
endfunction
call t#before_each(function('s:before'))

function! s:after() abort
  call t#restore_stubs()
  call t#clean_buffers()
endfunction
call t#after_each(function('s:after'))

call t#describe('helm releases')

function! s:test_list() abort
  call t#open('kube://helm-releases')
  call t#wait_buf_name(s:RELEASES)
  call assert_equal([s:LIST . ' -o json -A'], t#calls_matching('^helm'))
  call assert_equal(2, line('$'))
  call assert_match('^ns1\s\+web\s\+3\s\+deployed\s\+web-1\.2\.0\s\+1\.2\s\+\d\+d\s*$', getline(1))

  call t#reset_kubectl()
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
  call t#respond('helm *list*', {'stdout': '[]'})
  call t#open('kube://ns/ns1/helm-releases')
  call assert_equal([s:LIST . ' -o json -n ns1'], t#calls_matching('^helm'))
  call assert_equal('No releases found', t#status())
endfunction
call t#it("are listed in all namespaces, or in one, of the buffer's context", function('s:test_list'))

function! s:test_failed() abort
  call t#open(s:RELEASES)
  let diagnostics = t#diagnostics()
  call assert_equal(1, len(diagnostics))
  call assert_equal([2, 'error'], diagnostics[0][0:1])
endfunction
call t#it('report failed releases as diagnostics', function('s:test_failed'))

function! s:test_sorted() abort
  call t#respond('helm *list*', {'stdout': json_encode([
        \ {'name': 'a', 'namespace': 'ns2', 'revision': '1', 'status': 'deployed'},
        \ {'name': 'b', 'namespace': 'ns1', 'revision': '1', 'status': 'deployed'},
        \ {'name': 'c', 'namespace': 'ns1', 'revision': '1', 'status': 'deployed'},
        \ ])})
  call t#open(s:RELEASES)
  call assert_equal(['ns1/b', 'ns1/c', 'ns2/a'], map(t#lines(), 'join(split(v:val)[0:1], "/")'))
endfunction
call t#it('are sorted by namespace, then name, as helm sorts by name only', function('s:test_sorted'))

function! s:test_ages() abort
  call assert_equal(helm#format#age('2026-01-01 00:00:00.5 +0000 UTC'), helm#format#age('2026-01-01 08:00:00.123456 +0800 CST'))
  call assert_equal(helm#format#age('2026-01-01T00:00:00Z'), helm#format#age('2026-01-01T03:00:00.1+03:00'))
  call assert_equal('', helm#format#age(v:null))
endfunction
call t#it('ages account for the time zone helm outputs', function('s:test_ages'))

function! s:test_views_keys() abort
  call t#open(s:RELEASES)
  call t#press_on('web', "\<CR>")
  call t#wait_buf_name(s:WEB . '/manifest')
  call t#wait_loaded()
  call assert_equal(['---', 'kind: ConfigMap'], t#lines())
  call assert_equal('yaml', &filetype)
  call assert_equal(0, &modifiable)

  call t#open(s:RELEASES)
  call t#press_on('web', 'gd')
  call t#wait_buf_name(s:WEB . '/values')
  call t#wait_loaded()
  call assert_equal(['replicas: 2'], t#lines())

  call t#press('-')
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/helm-releases')
endfunction
call t#it('<CR> opens the manifest, gd the values, - goes back to the list', function('s:test_views_keys'))

function! s:test_status() abort
  call t#open(s:RELEASES)
  call t#press_on('web', 'K')
  let float = t#wait_float('STATUS: deployed')
  call assert_equal(['NAME: web', 'STATUS: deployed'], getbufline(winbufnr(float), 1, '$'))
  call kube#compat#close_float(float)
endfunction
call t#it('K shows the status', function('s:test_status'))

function! s:test_views() abort
  call t#open(s:WEB)
  call assert_equal(['NAME: web', 'STATUS: deployed'], t#lines())
  call t#open(s:WEB . '/notes')
  call assert_equal(['NOTES:', 'Thanks'], t#lines())
  call t#open(s:WEB . '/values?all=true')
  call t#open(s:WEB . '/manifest?revision=2')
  call assert_equal([
        \ 'helm --kube-context ctx-a status web -n ns1',
        \ 'helm --kube-context ctx-a get notes web -n ns1',
        \ 'helm --kube-context ctx-a get values web -o yaml --all -n ns1',
        \ 'helm --kube-context ctx-a get manifest web --revision=2 -n ns1',
        \ ], t#calls_matching('^helm'))
endfunction
call t#it('views are buffers of their own', function('s:test_views'))

function! s:test_uninstall_line() abort
  call t#respond('helm * uninstall *', {'stdout': 'release "db" uninstalled'})
  let seen = t#prompts()
  call t#open(s:RELEASES)
  call t#press_on('db', 'dd')
  write
  call t#wait_call(' uninstall ')
  call assert_equal(["Apply the changes (context: ctx-a)?\n  Uninstall helm release ns2/db"], seen)
  call assert_equal(['helm --kube-context ctx-a uninstall db -n ns2'], t#calls_matching(' uninstall '))
endfunction
call t#it('deleting a line and :w uninstalls the release after confirming', function('s:test_uninstall_line'))

function! s:test_operations() abort
  call t#open(s:RELEASES)
  call t#press_on('web', '')
  let titles = t#operation('Show history')
  call assert_equal([
        \ 'Show manifest',
        \ 'Show values',
        \ 'Show all values',
        \ 'Show notes',
        \ 'Show status',
        \ 'Show history',
        \ 'Rollback to the previous revision',
        \ 'Uninstall',
        \ ], titles)
  call t#wait_buf_name(s:WEB . '/history')
  call t#wait_loaded()
  call assert_equal(3, line('$'))
  call assert_match('^3\s\+\d\+d\s\+deployed\s\+web-1\.2\.0\s\+1\.2\s\+Upgrade complete$', getline(3))
  " A table, like other lists
  call assert_equal(0, &wrap)
endfunction
call t#it('operations are offered by gra', function('s:test_operations'))

function! s:test_rollback() abort
  call t#respond('helm *rollback*', {'stdout': 'Rollback was a success! Happy Helming!'})
  let seen = t#prompts()
  call t#open(s:RELEASES)
  call t#press_on('web', '')
  call t#operation('Rollback to the previous revision')
  call t#wait_call('rollback')

  call t#open(s:WEB . '/history')
  call t#press_on('Install complete', '')
  call t#operation('Rollback to revision 1')
  call t#wait_call('rollback', 2)
  call assert_equal([
        \ 'Roll back helm release ns1/web (context: ctx-a)?',
        \ 'Roll back helm release ns1/web to revision 1 (context: ctx-a)?',
        \ ], seen)
  call assert_equal([
        \ 'helm --kube-context ctx-a rollback web -n ns1',
        \ 'helm --kube-context ctx-a rollback web 1 -n ns1',
        \ ], t#calls_matching('rollback'))
endfunction
call t#it('roll back to the previous revision, or to one of the history', function('s:test_rollback'))

function! s:test_revision_manifest() abort
  call t#open(s:WEB . '/history')
  call t#press_on('Install complete', "\<CR>")
  call t#wait_buf_name(s:WEB . '/manifest?revision=1')
endfunction
call t#it('<CR> on a revision opens its manifest', function('s:test_revision_manifest'))

function! s:test_uninstall_several() abort
  call t#respond('helm * uninstall *', {'stdout': 'uninstalled'})
  call t#prompts()
  call t#open(s:RELEASES)
  let titles = t#operation('Uninstall 2 releases', 1, 2)
  call t#wait_call(' uninstall ', 2)
  call assert_equal(['Uninstall 2 releases'], titles)
endfunction
call t#it('uninstall several releases at once', function('s:test_uninstall_several'))

function! s:test_visual_operations() abort
  call t#respond('helm * uninstall *', {'stdout': 'uninstalled'})
  let g:t_offered = []
  call t#answer_prompts({items, opts -> index(items, 'Yes') >= 0 ? 'Yes' : [extend(g:t_offered, items), items[-1]][1]}, v:null)
  call t#open(s:RELEASES)
  call t#press('ggVjgra')
  call assert_equal(['Uninstall 2 releases'], g:t_offered)
  call t#wait_call(' uninstall ', 2)
endfunction
call t#it('gra on a visual selection offers the operations on all its rows', function('s:test_visual_operations'))

function! s:test_command() abort
  Kube get helm-releases namespace=ns1
  call t#wait_loaded()
  call t#wait_buf_name('kube://context/ctx-a/namespaces/ns1/helm-releases')
  Kube get helm
  call t#wait_buf_name(s:RELEASES)
  call t#wait_for({-> !bufexists('kube://helm')}, 'the alias buffer to be wiped')
endfunction
call t#it(':Kube get helm-releases, or helm for short, opens the list', function('s:test_command'))
