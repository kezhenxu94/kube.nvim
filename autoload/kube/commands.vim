" The :Kube command.

function! s:params(args) abort
  let params = {}
  for arg in a:args
    let match = matchlist(arg, '^\([^=]\+\)=\(.\+\)$')
    if !empty(match)
      let params[match[1]] = match[2]
    endif
  endfor
  return params
endfunction

" Parse the arguments of the subcommands, into the arguments of their function.
function! kube#commands#parse(command, args, bang) abort
  if a:command ==# 'get'
    return [get(a:args, 0, ''), s:params(a:args[1:])]
  elseif a:command ==# 'delete'
    return [get(a:args, 0, ''), get(a:args, 1, ''), s:params(a:args[2:])]
  elseif a:command ==# 'context'
    return [get(a:args, 0, '')]
  elseif a:command ==# 'apply'
    return [a:bang]
  endif
  return []
endfunction

let s:COMMANDS = ['get', 'delete', 'context', 'apply', 'diff', 'portforwards']

function! kube#commands#run(args, bang) abort
  let args = split(a:args, ' ')
  let command = empty(args) ? '' : remove(args, 0)
  if index(s:COMMANDS, command) < 0
    call kube#ui#notify('No such command: ' . command, 'error')
    return
  endif
  call call(function('s:' . command), kube#commands#parse(command, args, a:bang))
endfunction

function! s:filter(items, arglead, ignorecase) abort
  if empty(a:arglead)
    return a:items
  endif
  let prefix = a:ignorecase ? tolower(a:arglead) : a:arglead
  return filter(copy(a:items), (a:ignorecase ? 'stridx(tolower(v:val), prefix)' : 'stridx(v:val, prefix)') . ' == 0')
endfunction

function! s:kinds(helm) abort
  let kinds = kube#kubectl#api_resources_sync()
  if a:helm && executable('helm')
    let kinds = ['helm-releases', 'helm'] + kinds
  endif
  return kinds
endfunction

function! kube#commands#complete(arglead, cmdline, cursorpos) abort
  let args = split(a:cmdline, ' ', 1)[1:]
  if len(args) <= 1
    return s:filter(copy(s:COMMANDS), a:arglead, 0)
  endif
  let command = remove(args, 0)
  if command ==# 'get'
    return len(args) <= 1 ? s:filter(s:kinds(1), a:arglead, 1) : s:filter(['namespace', 'selector'], a:arglead, 0)
  elseif command ==# 'delete'
    if len(args) <= 1
      return s:filter(s:kinds(0), a:arglead, 1)
    elseif len(args) == 2
      " Without namespace=, :Kube delete deletes in the default namespace
      return s:filter(kube#kubectl#resource_names_sync(args[0], 'default'), a:arglead, 0)
    endif
    return s:filter(['namespace', 'selector'], a:arglead, 0)
  elseif command ==# 'context'
    return s:filter(kube#kubectl#context_names_sync(), a:arglead, 0)
  endif
  return []
endfunction

" Open the list of {kind}, in params.namespace if given.
function! s:get(kind, params) abort
  let params = copy(a:params)
  let namespace = get(params, 'namespace', '')
  silent! call remove(params, 'namespace')
  call kube#utils#open({'namespace': namespace, 'kind': a:kind, 'params': params})
endfunction

function! s:delete(kind, name, params) abort
  let context = kube#kubectl#get_current_context()
  let namespace = get(a:params, 'namespace', 'default')
  let target = printf('%s: %s/%s (context: %s)', a:kind, namespace, a:name, context)
  call kube#ui#confirm(printf('Delete %s?', target), function('s:on_delete', [context, a:kind, a:name, namespace, target]))
endfunction

function! s:on_delete(context, kind, name, namespace, target, confirmed) abort
  if a:confirmed
    call kube#kubectl#delete(a:context, a:kind, a:name, a:namespace,
          \ {result -> result is v:null ? 0 : kube#ui#notify('Deleted ' . a:target)},
          \ {err -> kube#ui#notify(printf("Failed to delete %s: \n%s", a:target, err), 'error')})
  endif
endfunction

" Switch to {context}, select it when ''.
function! s:context(context) abort
  if !empty(a:context)
    call s:use_context(a:context)
    return
  endif
  call kube#kubectl#get_config(function('s:on_config'))
endfunction

function! s:use_context(context) abort
  call kube#kubectl#use_context(a:context, {result -> kube#ui#notify('Switched to context: ' . a:context)})
endfunction

function! s:on_config(result) abort
  if a:result is v:null
    call kube#ui#notify('No config found', 'error')
    return
  endif
  let config = json_decode(a:result)
  let contexts = kube#utils#list(config, 'contexts')
  if empty(contexts)
    call kube#ui#notify('No contexts found', 'error')
    return
  endif
  let current = kube#kubectl#context()
  let current = type(current) == v:t_string ? current : kube#utils#get(config, 'current-context', '')
  call kube#ui#select(contexts, {
        \ 'prompt': printf('Select context (current: %s)', current),
        \ 'format_item': {item -> (item.name ==# current ? '* ' : '  ') . item.name},
        \ }, {choice, index -> choice is v:null ? 0 : s:use_context(choice.name)})
endfunction

" Apply the current buffer as a manifest to the current context, {force}
" skips the confirmation.
function! s:apply(force) abort
  let context = kube#kubectl#get_current_context()
  let name = expand('%:t')
  let title = printf('Apply %s (context: %s)?', empty(name) ? 'buffer' : name, context)
  call kube#apply#with_temp_file(getline(1, '$'),
        \ {file, Cleanup -> kube#apply#apply(context, v:null, file, {'force': a:force, 'title': title}, {applied -> Cleanup()})})
endfunction

" Show the diff of the current buffer as a manifest against the current context.
function! s:diff() abort
  let context = kube#kubectl#get_current_context()
  call kube#apply#with_temp_file(getline(1, '$'), function('s:on_diff_file', [context]))
endfunction

function! s:on_diff_file(context, file, Cleanup) abort
  call kube#kubectl#diff(a:context, v:null, a:file, function('s:show_diff', [a:Cleanup]),
        \ {err -> kube#ui#notify('Failed to diff: ' . err, 'error')})
endfunction

function! s:show_diff(Cleanup, diff) abort
  call a:Cleanup()
  if a:diff is v:null
    return
  elseif empty(a:diff)
    call kube#ui#notify('No changes')
  else
    call kube#apply#show_split(split(trim(a:diff), "\n"), 'diff')
  endif
endfunction

function! s:portforwards() abort
  edit kube://portforwards
endfunction
