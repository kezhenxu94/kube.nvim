" Where jumps from kube buffers go.

" The buffer one level up: subresource / resource -> list in its namespace ->
" list in all namespaces -> namespaces -> api-resources. '' if none.
function! kube#navigation#parent_name(kbuf) abort
  let k = a:kbuf
  if !empty(k.resource_name)
    return kube#utils#buf_name({'context': k.context, 'namespace': k.namespace, 'kind': k.resource_kind})
  elseif k.namespace !=# 'all'
    return kube#utils#buf_name({'context': k.context, 'kind': k.resource_kind, 'params': k.params})
  elseif k.resource_kind ==# 'namespaces'
    return kube#utils#buf_name({'context': k.context, 'kind': 'api-resources'})
  elseif k.resource_kind !=# 'api-resources'
    return kube#utils#buf_name({'context': k.context, 'kind': 'namespaces'})
  endif
  return ''
endfunction

" The list of the resource type of an api-resources row, in the buffer's
" namespace if namespaced.
function! kube#navigation#api_resource_target(kbuf, item) abort
  return kube#utils#buf_name({'context': a:kbuf.context, 'namespace': a:item.namespaced ? a:kbuf.namespace : '', 'kind': a:item.name})
endfunction

" The cell at {lnum} and the 0-indexed byte {col}, or just the item of the
" row between cells: {item, column}, {} if none.
function! s:cell_at(kbuf, lnum, col) abort
  for id in kube#compat#cells_at(a:kbuf.bufnr, a:lnum, a:col)
    if has_key(a:kbuf.cells, id)
      return a:kbuf.cells[id]
    endif
  endfor
  let item = kube#table#item_at(a:kbuf, a:lnum)
  return item is v:null ? {} : {'item': item, 'column': ''}
endfunction

" The buffer the cell at {lnum} and the 0-indexed byte {col} refers to, like a
" tag: NAMESPACE -> the same list in that namespace, NODE -> the node, an
" event's OBJECT -> that object, a namespace row -> its pods, a resource type
" -> its list, a Helm release -> its values, a revision -> its manifest,
" anything else -> the resource's definition (YAML). '' if none.
function! kube#navigation#tag_target(kbuf, lnum, col) abort
  let k = a:kbuf
  let cell = s:cell_at(k, a:lnum, a:col)
  let item = get(cell, 'item', v:null)
  if type(item) != v:t_dict
    return ''
  endif
  let kind = get(item, 'kind', '')
  if kind ==# 'APIResource'
    return kube#navigation#api_resource_target(k, item)
  elseif kind ==# 'HelmRelease'
    if cell.column ==# 'NAMESPACE'
      return kube#utils#buf_name({'context': k.context, 'namespace': item.namespace, 'kind': 'helm-releases'})
    endif
    return kube#utils#buf_name({'context': k.context, 'namespace': item.namespace, 'kind': 'helm-releases',
          \ 'name': item.name, 'subresource': 'values'})
  elseif kind ==# 'HelmRevision'
    return kube#utils#buf_name({'context': k.context, 'namespace': item.namespace, 'kind': 'helm-releases',
          \ 'name': item.release, 'subresource': 'manifest', 'params': {'revision': item.revision}})
  elseif !has_key(item, 'metadata')
    return ''
  endif

  let namespace = kube#utils#get(item.metadata, 'namespace', '')
  if cell.column ==# 'NAMESPACE' && !empty(namespace) && empty(k.resource_name)
    return kube#utils#buf_name({'context': k.context, 'namespace': namespace, 'kind': k.resource_kind, 'params': k.params})
  endif
  if cell.column ==# 'OBJECT' && has_key(item, 'involvedObject')
    let object = item.involvedObject
    return kube#utils#buf_name({'context': k.context, 'namespace': kube#utils#get(object, 'namespace', ''),
          \ 'kind': kube#utils#resource_type(object), 'name': object.name, 'params': {'output': 'yaml'}})
  endif
  let node = kube#utils#dig(item, 'spec.nodeName', '')
  if cell.column ==# 'NODE' && !empty(node)
    return kube#utils#buf_name({'context': k.context, 'kind': 'node', 'name': node})
  endif
  if kind ==# 'Namespace'
    return kube#utils#buf_name({'context': k.context, 'namespace': item.metadata.name, 'kind': 'pods'})
  endif
  return kube#utils#buf_name({'context': k.context, 'namespace': namespace, 'kind': kube#utils#resource_type(item),
        \ 'name': item.metadata.name, 'params': {'output': 'yaml'}})
endfunction

" 'tagfunc' of kube buffers, so that <C-]>, <C-w>], <C-t> and the tag stack
" work as usual.
function! kube#navigation#tagfunc(pattern, flags, info) abort
  let kbuf = kube#buffer#get(bufnr(''))
  " Only jumps from the cursor are resolved here, :tag {name} uses the tags
  " files
  if empty(kbuf) || a:flags !~# 'c'
    return v:null
  endif
  let target = kube#navigation#tag_target(kbuf, line('.'), col('.') - 1)
  return empty(target) ? [] : [{'name': a:pattern, 'filename': target, 'cmd': '1'}]
endfunction
