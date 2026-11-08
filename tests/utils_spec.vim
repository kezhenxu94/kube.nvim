call t#describe('utils.buf_name')

function! s:test_current_context() abort
  call assert_equal('kube://deployments', kube#utils#buf_name({'kind': 'deployments'}))
  call assert_equal('kube://deployments', kube#utils#buf_name({'kind': 'deployments', 'namespace': 'all'}))
  call assert_equal('kube://deployments', kube#utils#buf_name({'kind': 'deployments', 'namespace': 'ALL'}))
endfunction
call t#it('builds a current-context, all-namespaces name', function('s:test_current_context'))

function! s:test_namespaced() abort
  call assert_equal('kube://context/prod/namespaces/ns1/pod/web-1/logs',
        \ kube#utils#buf_name({'context': 'prod', 'namespace': 'ns1', 'kind': 'pod', 'name': 'web-1', 'subresource': 'logs'}))
endfunction
call t#it('builds a namespaced name with a context', function('s:test_namespaced'))

function! s:test_encodes() abort
  call assert_equal('kube://context/arn%3aaws%3aeks%3aus-east-1%3a1%3acluster%2fprod/pods',
        \ kube#utils#buf_name({'context': 'arn:aws:eks:us-east-1:1:cluster/prod', 'kind': 'pods'}))
  call assert_equal('a/b:c é', kube#utils#uri_decode(kube#utils#uri_encode('a/b:c é')))
endfunction
call t#it('encodes contexts containing / and :', function('s:test_encodes'))

function! s:test_subresource_without_name() abort
  call assert_equal('kube://pods', kube#utils#buf_name({'kind': 'pods', 'subresource': 'logs'}))
endfunction
call t#it('ignores a subresource without a name', function('s:test_subresource_without_name'))

function! s:test_params() abort
  call assert_equal('kube://pod/x?edit=true&output=yaml',
        \ kube#utils#buf_name({'kind': 'pod', 'name': 'x', 'params': {'output': 'yaml', 'edit': v:true}}))
  call assert_equal('kube://pods', kube#utils#buf_name({'kind': 'pods', 'params': {}}))
endfunction
call t#it('sorts params and stringifies values', function('s:test_params'))

call t#describe('utils.resource_type')

function! s:test_core_group() abort
  call assert_equal('pod', kube#utils#resource_type({'apiVersion': 'v1', 'kind': 'Pod'}))
endfunction
call t#it('uses the bare kind for the core group', function('s:test_core_group'))

function! s:test_qualifies() abort
  call assert_equal('deployment.apps', kube#utils#resource_type({'apiVersion': 'apps/v1', 'kind': 'Deployment'}))
  call assert_equal('gateway.networking.istio.io', kube#utils#resource_type({'apiVersion': 'networking.istio.io/v1', 'kind': 'Gateway'}))
  call assert_equal('gateway.gateway.networking.k8s.io',
        \ kube#utils#resource_type({'apiVersion': 'gateway.networking.k8s.io/v1', 'kind': 'Gateway'}))
endfunction
call t#it('qualifies kinds with their API group', function('s:test_qualifies'))

function! s:test_missing_api_version() abort
  call assert_equal('pod', kube#utils#resource_type({'kind': 'Pod'}))
endfunction
call t#it('handles a missing apiVersion', function('s:test_missing_api_version'))

call t#describe('utils.portforward_key')

function! s:test_portforward_key() abort
  call assert_notequal(kube#utils#portforward_key('a', 'ns', 'pod', 'x'), kube#utils#portforward_key('b', 'ns', 'pod', 'x'))
  call assert_notequal(kube#utils#portforward_key('a', 'ns', 'pod', 'x'), kube#utils#portforward_key('a', 'ns', 'deployment.apps', 'x'))
endfunction
call t#it('separates contexts and resource types', function('s:test_portforward_key'))

call t#describe('utils.open')

function! s:test_open_escapes() abort
  " Avoid triggering the plugin, only the name matters here
  augroup kube_test
    autocmd!
    autocmd BufReadCmd kube://* :
  augroup END
  autocmd! kube_autocmds BufReadCmd
  try
    call kube#utils#open({'context': 'a/b:c', 'kind': 'pods', 'params': {'selector': 'x!=y'}})
    call assert_equal('kube://context/a%2fb%3ac/pods?selector=x!=y', bufname(''))
  finally
    autocmd! kube_test
    runtime plugin/kube.vim
    silent! %bwipeout!
  endtry
endfunction
call t#it('does not expand % and # in names', function('s:test_open_escapes'))

call t#describe('utils.calculate_age')

function! s:ago(seconds) abort
  " The time zone is UTC, see the Makefile
  return strftime('%Y-%m-%dT%H:%M:%SZ', localtime() - a:seconds)
endfunction

function! s:test_age() abort
  call assert_equal('5s', kube#utils#calculate_age(s:ago(5)))
  call assert_equal('2m5s', kube#utils#calculate_age(s:ago(125)))
  call assert_equal('3h', kube#utils#calculate_age(s:ago(3 * 3600 + 10)))
  call assert_equal('4d', kube#utils#calculate_age(s:ago(4 * 86400 + 10)))
  call assert_equal(0, kube#utils#parse_time('1970-01-01T00:00:00Z'))
  call assert_equal(1767225600, kube#utils#parse_time('2026-01-01T00:00:00Z'))
endfunction
call t#it('formats seconds, minutes, hours and days', function('s:test_age'))

call t#describe('utils.get_winbar')

function! s:header_buffer(formatted) abort
  enew
  file kube://context/c/pods
  let kbuf = kube#buffer#new(bufnr(''))
  let kbuf.header_row = {'formatted': a:formatted, 'highlight': 'KubeHeader'}
  return kbuf
endfunction

function! s:clean_header_buffer() abort
  call kube#buffer#forget(bufnr(''))
  silent! %bwipeout!
endfunction
call t#after_each(function('s:clean_header_buffer'))

function! s:test_winbar_without_number() abort
  let kbuf = s:header_buffer('NAME  AGE')
  setlocal nonumber signcolumn=no
  call assert_equal('%#KubeHeader#NAME  AGE%=%#Comment#', kube#utils#get_winbar(kbuf.bufnr, win_getid()))
endfunction
call t#it('works without a number column', function('s:test_winbar_without_number'))

function! s:test_winbar_number() abort
  let kbuf = s:header_buffer('NAME')
  setlocal number
  call assert_match('^ \+%#KubeHeader#NAME%=%#Comment#$', kube#utils#get_winbar(kbuf.bufnr, win_getid()))
endfunction
call t#it('pads for the number column', function('s:test_winbar_number'))
