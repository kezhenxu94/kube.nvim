" Buffer names, JSON values, times.

" {dict}[{key}], or {default} when missing or null.
function! kube#utils#get(dict, key, default) abort
  if type(a:dict) != v:t_dict
    return a:default
  endif
  let value = get(a:dict, a:key, v:null)
  return value is v:null ? a:default : value
endfunction

" The value at the dotted {path} of {dict}, or {default}.
function! kube#utils#dig(dict, path, default) abort
  let value = a:dict
  for key in split(a:path, '\.')
    let value = kube#utils#get(value, key, v:null)
    if value is v:null
      return a:default
    endif
  endfor
  return value
endfunction

" The list at {key} of {dict}, [] when missing or null.
function! kube#utils#list(dict, key) abort
  let value = kube#utils#get(a:dict, a:key, [])
  return type(value) == v:t_list ? value : []
endfunction

" A buffer name:
" kube://[context/{context}/][namespaces/{ns}/]{kind}[/{name}[/{subresource}]][?{params}]
" {opts}: context (none for the current one), namespace (none or 'all' for
" cluster-scoped / all namespaces), kind, name, subresource, params.
function! kube#utils#buf_name(opts) abort
  let parts = ['kube:/']
  let context = kube#utils#get(a:opts, 'context', '')
  if !empty(context)
    " Encoded as context names may contain / and :, e.g. EKS ARNs
    call extend(parts, ['context', resource#uri_encode(context)])
  endif
  let namespace = kube#utils#get(a:opts, 'namespace', '')
  if !empty(namespace) && tolower(namespace) !=# 'all'
    call extend(parts, ['namespaces', namespace])
  endif
  call add(parts, a:opts.kind)
  let name = kube#utils#get(a:opts, 'name', '')
  if !empty(name)
    call add(parts, name)
    let subresource = kube#utils#get(a:opts, 'subresource', '')
    if !empty(subresource)
      call add(parts, subresource)
    endif
  endif
  let buf_name = join(parts, '/')

  let params = kube#utils#get(a:opts, 'params', {})
  let query = sort(map(items(params), 'v:val[0] . "=" . resource#to_string(v:val[1])'))
  if !empty(query)
    let buf_name .= '?' . join(query, '&')
  endif
  return buf_name
endfunction

" Edit the buffer of the name built from {opts}.
function! kube#utils#open(opts) abort
  call resource#open(kube#utils#buf_name(a:opts))
endfunction

" Key of the port forwards of a resource, see kube#portforward#all().
function! kube#utils#portforward_key(context, namespace, resource_type, name) abort
  return join([a:context, a:namespace, a:resource_type, a:name], '/')
endfunction

" The fully qualified resource type of a resource object, e.g. pod or
" deployment.apps, so kubectl never resolves it to a same-named kind of
" another API group.
function! kube#utils#resource_type(resource) abort
  let kind = tolower(a:resource.kind)
  let group = matchstr(kube#utils#get(a:resource, 'apiVersion', ''), '^\zs.\+\ze/[^/]\+$')
  return empty(group) ? kind : kind . '.' . group
endfunction

" The seconds since the epoch of an RFC 3339 UTC timestamp, e.g.
" 2026-01-01T00:00:00Z.
function! kube#utils#parse_time(timestamp) abort
  let t = a:timestamp
  let [year, month, day] = [str2nr(t[0:3]), str2nr(t[5:6]), str2nr(t[8:9])]
  let seconds = str2nr(t[11:12]) * 3600 + str2nr(t[14:15]) * 60 + str2nr(t[17:18])
  " Days from the civil date, see http://howardhinnant.github.io/date_algorithms.html
  let y = month <= 2 ? year - 1 : year
  let era = (y >= 0 ? y : y - 399) / 400
  let yoe = y - era * 400
  let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return (era * 146097 + doe - 719468) * 86400 + seconds
endfunction

" e.g. 42s, 5m3s, 2h, 7d
function! kube#utils#format_duration(seconds) abort
  let seconds = type(a:seconds) == v:t_float ? float2nr(a:seconds) : a:seconds
  if seconds < 60
    return printf('%ds', seconds)
  elseif seconds < 3600
    return printf('%dm%ds', seconds / 60, seconds % 60)
  elseif seconds < 86400
    return printf('%dh', seconds / 3600)
  endif
  return printf('%dd', seconds / 86400)
endfunction

" The time since {created}, an RFC 3339 UTC timestamp.
function! kube#utils#calculate_age(created) abort
  return kube#utils#format_duration(localtime() - kube#utils#parse_time(a:created))
endfunction
