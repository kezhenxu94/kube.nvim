" Parse a buffer name without loading it.
function! s:parse(name) abort
  let parsed = kube#provider#parse(a:name)
  return filter(parsed, '!empty(v:val)')
endfunction

call t#describe('KubeBuffer name parsing')

function! s:test_all_namespaces() abort
  call assert_equal({'context': 'c', 'namespace': 'all', 'resource_kind': 'deployments'}, s:parse('kube://context/c/deployments'))
endfunction
call t#it('parses an all-namespaces list', function('s:test_all_namespaces'))

function! s:test_subresource() abort
  call assert_equal({
        \ 'context': 'prod',
        \ 'namespace': 'ns1',
        \ 'resource_kind': 'pod',
        \ 'resource_name': 'web-1',
        \ 'subresource_kind': 'logs',
        \ 'params': {'container': 'app', 'follow': v:true},
        \ }, s:parse('kube://context/prod/namespaces/ns1/pod/web-1/logs?container=app&follow=true'))
endfunction
call t#it('parses a namespaced subresource with context', function('s:test_subresource'))

function! s:test_decodes() abort
  call assert_equal('arn:aws:eks:us-east-1:1:cluster/prod',
        \ s:parse('kube://context/arn%3Aaws%3Aeks%3Aus-east-1%3A1%3Acluster%2Fprod/pods').context)
endfunction
call t#it('decodes the context', function('s:test_decodes'))

function! s:test_cluster_scoped() abort
  call assert_equal({'context': 'c', 'namespace': 'all', 'resource_kind': 'node', 'resource_name': 'n1'}, s:parse('kube://context/c/node/n1'))
endfunction
call t#it('parses cluster-scoped resources', function('s:test_cluster_scoped'))

function! s:test_namespace_object() abort
  call assert_equal({'context': 'c', 'namespace': 'all', 'resource_kind': 'namespaces', 'resource_name': 'ns1'},
        \ s:parse('kube://context/c/namespaces/ns1'))
endfunction
call t#it('treats namespaces/<name> as the namespace object', function('s:test_namespace_object'))

function! s:test_flag_params() abort
  call assert_equal({'selector': 'app=web,tier=fe', 'edit': v:true, 'follow': v:false, 'output': 'yaml'},
        \ s:parse('kube://context/c/pods?selector=app=web,tier=fe&edit&follow=false&output=yaml').params)
endfunction
call t#it('converts flag params to booleans and keeps values with =', function('s:test_flag_params'))

function! s:fails(name) abort
  try
    call kube#provider#parse(a:name)
    return 0
  catch /^Invalid buffer name/
    return 1
  endtry
endfunction

function! s:test_rejects() abort
  " Names without a context are pinned by BufReadCmd before being parsed
  call assert_true(s:fails('kube://pods'))
  call assert_true(s:fails('kube://context/c'))
  call assert_true(s:fails('kube://'))
endfunction
call t#it('rejects names without a context or kind', function('s:test_rejects'))

function! s:test_same_instance() abort
  call t#reset_kubectl()
  call t#respond('*get pods*', {'stdout': '{"items": []}'})
  try
    call t#open('kube://context/c/pods')
    let kbuf = t#kbuf()
    edit
    call t#wait_loaded()
    call assert_true(t#kbuf() is kbuf)
  finally
    call t#clean_buffers()
  endtry
endfunction
call t#it('returns the same instance for the same buffer', function('s:test_same_instance'))

call t#describe('canonical buffer names')

function! s:before_canonical() abort
  call t#reset_kubectl()
  call kube#kubectl#set_context(v:null)
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
endfunction
call t#before_each(function('s:before_canonical'))

function! s:canonical(name) abort
  return kube#provider#canonical(a:name)
endfunction

function! s:test_pins() abort
  call assert_equal('kube://context/ctx-a/pods', s:canonical('kube://pods'))
  call assert_equal('kube://context/c/pods', s:canonical('kube://context/c/pods'))
  call assert_equal('kube://portforwards', s:canonical('kube://portforwards'))
endfunction
call t#it('pins names without a context to the current one', function('s:test_pins'))

function! s:test_ns() abort
  call assert_equal('kube://context/ctx-a/namespaces/prod/pods', s:canonical('kube://ns/prod/pods'))
  call assert_equal('kube://context/c/namespaces/prod/pods?selector=app', s:canonical('kube://context/c/ns/prod/pods?selector=app'))
  call assert_equal('kube://context/ctx-a/namespaces/prod', s:canonical('kube://ns/prod'))
  call assert_equal('kube://context/ctx-a/namespaces', s:canonical('kube://ns'))
  call assert_equal('kube://context/ctx-a/namespaces?selector=a', s:canonical('kube://ns?selector=a'))
  call assert_equal('kube://context/ctx-a/nsx/a', s:canonical('kube://nsx/a'))
  call assert_equal('kube://context/ctx-a/pods/ns', s:canonical('kube://pods/ns'))
endfunction
call t#it('expands ns to namespaces', function('s:test_ns'))

function! s:test_ctx() abort
  call assert_equal('kube://context/c/pods', s:canonical('kube://ctx/c/pods'))
  call assert_equal('kube://context/c/namespaces/prod/pods', s:canonical('kube://ctx/c/ns/prod/pods'))
  call assert_equal('kube://context/c/api-resources', s:canonical('kube://ctx/c'))
  " A namespace named ctx, a pod named ctx
  call assert_equal('kube://context/ctx-a/namespaces/ctx/pods', s:canonical('kube://ns/ctx/pods'))
  call assert_equal('kube://context/ctx-a/pods/ctx', s:canonical('kube://pods/ctx'))
endfunction
call t#it('expands ctx to context', function('s:test_ctx'))

function! s:test_helm() abort
  call assert_equal('kube://context/ctx-a/helm-releases', s:canonical('kube://helm'))
  call assert_equal('kube://context/c/namespaces/prod/helm-releases', s:canonical('kube://context/c/ns/prod/helm'))
  call assert_equal('kube://context/ctx-a/namespaces/prod/helm-releases/web/values?all=true',
        \ s:canonical('kube://ns/prod/helm/web/values?all=true'))
  call assert_equal('kube://context/ctx-a/helm-releases?a', s:canonical('kube://helm?a'))
  " A namespace named helm, a pod named helm
  call assert_equal('kube://context/ctx-a/namespaces/helm/pods', s:canonical('kube://ns/helm/pods'))
  call assert_equal('kube://context/ctx-a/namespaces/helm', s:canonical('kube://ns/helm'))
  call assert_equal('kube://context/ctx-a/pods/helm', s:canonical('kube://pods/helm'))
  call assert_equal('kube://context/ctx-a/helmcharts', s:canonical('kube://helmcharts'))
endfunction
call t#it('expands helm to helm-releases', function('s:test_helm'))

function! s:test_resource_types() abort
  call assert_equal('kube://context/ctx-a/api-resources', s:canonical('kube://'))
  call assert_equal('kube://context/c/api-resources', s:canonical('kube://context/c'))
  call assert_equal('kube://context/c/api-resources', s:canonical('kube://context/c/'))
endfunction
call t#it('lists the resource types without a kind', function('s:test_resource_types'))
