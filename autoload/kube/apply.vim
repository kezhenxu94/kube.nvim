" Apply manifests after showing their diff.

" Show {lines} in a scratch split below with {filetype}, staying in the
" current window. Returns the split's window id.
function! kube#apply#show_split(lines, filetype) abort
  let height = max([3, min([len(a:lines), &lines / 2])])
  execute 'belowright' height 'new'
  setlocal buftype=nofile bufhidden=wipe noswapfile nowrap nonumber norelativenumber
  call setline(1, a:lines)
  let &l:filetype = a:filetype
  setlocal nomodifiable
  let win = win_getid()
  wincmd p
  return win
endfunction

" Apply the manifest {file}, after showing its diff against the cluster and
" confirming unless {opts}.force. {opts}.title is the confirmation prompt.
" {Done}(applied), applied is also true when there was nothing to apply.
function! kube#apply#apply(context, namespace, file, opts, Done) abort
  if get(a:opts, 'force', 0)
    call s:apply(a:context, a:namespace, a:file, a:Done)
    return
  endif
  call kube#kubectl#diff(a:context, a:namespace, a:file,
        \ function('s:on_diff', [a:context, a:namespace, a:file, a:opts.title, a:Done]),
        \ {err -> kube#ui#notify('Failed to diff: ' . err, 'error')})
endfunction

function! s:apply(context, namespace, file, Done) abort
  call kube#kubectl#apply(a:context, a:namespace, a:file, function('s:on_applied', [a:Done]),
        \ {err -> kube#ui#notify('Failed to apply: ' . err, 'error')})
endfunction

function! s:on_applied(Done, result) abort
  if a:result isnot v:null
    call kube#ui#notify(trim(a:result))
  endif
  call a:Done(a:result isnot v:null)
endfunction

function! s:on_diff(context, namespace, file, title, Done, diff) abort
  if a:diff is v:null
    call a:Done(0)
    return
  elseif a:diff ==# ''
    call kube#ui#notify('No changes to apply')
    call a:Done(1)
    return
  endif
  let win = kube#apply#show_split(split(trim(a:diff), "\n"), 'diff')
  " Show the diff before prompting
  redraw
  call kube#ui#confirm(a:title, function('s:on_confirm', [win, a:context, a:namespace, a:file, a:Done]))
endfunction

function! s:on_confirm(win, context, namespace, file, Done, confirmed) abort
  if win_id2win(a:win) > 0
    call win_execute(a:win, 'close')
  endif
  if a:confirmed
    call s:apply(a:context, a:namespace, a:file, a:Done)
  else
    call a:Done(0)
  endif
endfunction

" Write {lines} to a temporary manifest and call {Fn}(file, Cleanup), the
" file is removed by Cleanup().
function! kube#apply#with_temp_file(lines, Fn) abort
  let file = tempname() . '.yaml'
  call writefile(a:lines, file)
  call a:Fn(file, {-> delete(file)})
endfunction
