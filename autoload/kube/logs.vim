" Logs of a resource: kube://.../{kind}/{name}/logs, params: container,
" follow, previous, all-containers, since, tail.

function! kube#logs#load(kbuf) abort
  let k = a:kbuf
  let params = k.params
  let opts = {
        \ 'container': get(params, 'container', ''),
        \ 'follow': get(params, 'follow', v:false) is v:true,
        \ 'previous': get(params, 'previous', v:false) is v:true,
        \ 'all_containers': get(params, 'all-containers', v:false) is v:true,
        \ 'since': get(params, 'since', ''),
        \ }
  if has_key(params, 'tail')
    let opts.tail = str2nr(params.tail)
  endif
  return resource#logs(k, kube#kubectl#logs_cmd(k.context, k.resource_kind, k.resource_name, k.namespace, opts), opts.follow)
endfunction
