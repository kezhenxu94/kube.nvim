call t#describe(':Kube argument parsing')

function! s:test_parse_get() abort
  call assert_equal(['pods', {'namespace': 'ns1', 'selector': 'app=web,tier=fe'}],
        \ kube#commands#parse('get', ['pods', 'namespace=ns1', 'selector=app=web,tier=fe'], 0))
endfunction
call t#it('parses get with key=value params whose values contain =', function('s:test_parse_get'))

function! s:test_parse_delete() abort
  call assert_equal(['pod', 'web-1', {'namespace': 'ns1'}], kube#commands#parse('delete', ['pod', 'web-1', 'namespace=ns1'], 0))
endfunction
call t#it('parses delete', function('s:test_parse_delete'))

function! s:test_parse_context() abort
  call assert_equal(['prod'], kube#commands#parse('context', ['prod'], 0))
endfunction
call t#it('parses context', function('s:test_parse_context'))

call t#describe(':Kube')

function! s:before() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
endfunction
call t#before_each(function('s:before'))
call t#after_each(function('t#restore_stubs'))

function! s:test_unknown() abort
  let messages = t#capture_notify()
  Kube nope
  call assert_equal([{'msg': 'No such command: nope', 'level': 'error'}], messages)
endfunction
call t#it('reports unknown subcommands', function('s:test_unknown'))

function! s:test_context() abort
  let messages = t#capture_notify()
  Kube context staging
  call assert_equal('staging', kube#kubectl#get_current_context())
  call assert_equal('Switched to context: staging', messages[0].msg)
endfunction
call t#it('context switches the context used for new buffers', function('s:test_context'))

function! s:test_context_prompt() abort
  call t#respond('*config view*', {'stdout': json_encode({'current-context': 'a', 'contexts': [{'name': 'a'}, {'name': 'b'}]})})
  let g:shown = v:null
  call t#answer_prompts({items, opts -> [execute('let g:shown = ' . string(map(copy(items), 'opts.format_item(v:val)'))), items[1]][1]}, v:null)
  call t#capture_notify()
  Kube context
  call t#wait_for('g:shown isnot v:null', 'context prompt')
  call assert_equal(['* a', '  b'], g:shown)
  call assert_equal('b', kube#kubectl#context())
endfunction
call t#it('context without a name prompts with the current one marked', function('s:test_context_prompt'))

function! s:test_delete() abort
  call kube#kubectl#set_context('prod')
  call t#respond('*delete*', {'stdout': 'deleted'})
  let prompts = t#prompts()
  call t#answer_prompts({items, opts -> [add(prompts, opts.prompt), 'Yes'][1]}, v:null)
  let messages = t#capture_notify()
  Kube delete pod web-1 namespace=ns1
  call t#wait_for({-> !empty(messages)}, 'delete notification')
  call assert_equal(['Delete pod: ns1/web-1 (context: prod)?'], prompts)
  call assert_equal(['--context prod delete pod web-1 -n ns1'], t#calls())
endfunction
call t#it('delete confirms with the context and deletes in it', function('s:test_delete'))

function! s:test_delete_declined() abort
  call kube#kubectl#set_context('prod')
  call t#answer_prompts({items, opts -> 'No'}, v:null)
  Kube delete pod web-1
  call t#wait(100)
  call assert_equal([], t#calls())
endfunction
call t#it('delete does nothing when not confirmed', function('s:test_delete_declined'))

call t#describe(':Kube completion')

function! s:before_completion() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context('completion-ctx')
endfunction
call t#before_each(function('s:before_completion'))

function! s:test_complete_subcommands() abort
  call assert_equal(['apply', 'context', 'delete', 'diff', 'get', 'portforwards'], sort(getcompletion('Kube ', 'cmdline')))
  call assert_equal(['get'], getcompletion('Kube g', 'cmdline'))
endfunction
call t#it('completes subcommands', function('s:test_complete_subcommands'))

function! s:test_complete_kinds() abort
  call t#respond('*api-resources*', {'stdout': "pods\nPodTemplates\ndeployments.apps\n"})
  call assert_equal(['pods', 'PodTemplates'], filter(getcompletion('Kube get po', 'cmdline'), 'v:val !~# "^helm"'))
  call assert_equal(['deployments.apps'], getcompletion('Kube delete de', 'cmdline'))
endfunction
call t#it('completes resource kinds case-insensitively', function('s:test_complete_kinds'))

function! s:test_complete_params() abort
  call assert_equal(['namespace', 'selector'], getcompletion('Kube get pods ', 'cmdline'))
  call assert_equal(['selector'], getcompletion('Kube get pods s', 'cmdline'))
endfunction
call t#it('completes get params after the kind', function('s:test_complete_params'))

function! s:test_complete_names() abort
  call t#respond('*get pods -o name -n default*', {'stdout': "pod/web-1\npod/web-2\npod/db\n"})
  call assert_equal(['web-1', 'web-2'], getcompletion('Kube delete pods we', 'cmdline'))
  call assert_equal(['--context completion-ctx get pods -o name -n default'], t#calls())
endfunction
call t#it('completes delete names in the default namespace', function('s:test_complete_names'))

function! s:test_complete_contexts() abort
  call t#respond('*get-contexts*', {'stdout': "prod\nstaging\n"})
  call assert_equal(['staging'], getcompletion('Kube context st', 'cmdline'))
endfunction
call t#it('completes context names', function('s:test_complete_contexts'))
