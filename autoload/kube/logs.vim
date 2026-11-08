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
  let job = kube#buffer#track(k, kube#kubectl#logs(k.context, k.resource_kind, k.resource_name, k.namespace, opts,
        \ function('s:on_logs', [k, opts.follow])))
  if !empty(job) && opts.follow
    let k.follow_job = job
    if bufnr('') == k.bufnr
      nnoremap <buffer> <silent> <C-c> :<C-u>call kube#logs#stop(bufnr(''))<CR>
    endif
  endif
  return job
endfunction

" Stop following the logs.
function! kube#logs#stop(bufnr) abort
  let k = kube#buffer#get(a:bufnr)
  let job = get(k, 'follow_job', {})
  if !empty(job) && has_key(k.jobs, job.id)
    call kube#compat#kill(job)
    call remove(k.jobs, job.id)
    call s:set_status(k, 'Stopped following logs, to restart, re-edit this buffer with `:e`')
  endif
endfunction

function! s:set_status(kbuf, text) abort
  call kube#compat#set_status(a:kbuf.bufnr, len(getbufline(a:kbuf.bufnr, 1, '$')), a:text, 'Comment')
endfunction

function! s:on_logs(kbuf, follow, result) abort
  let buf = a:kbuf.bufnr
  if !bufloaded(buf)
    return
  endif
  call kube#buffer#setup(a:kbuf)

  let lines = split(a:result, "\n", 1)
  if !a:follow
    call kube#buffer#set_lines(a:kbuf, lines, 1)
    return
  endif

  call setbufvar(buf, '&modifiable', 1)
  " Replace the trailing placeholder line, then add a new one for the status
  let start = len(getbufline(buf, 1, '$'))
  " Windows at the end keep showing the new lines, like tail -f
  let at_end = filter(win_findbuf(buf), 'getcurpos(v:val)[1] >= start - 1')
  call setbufline(buf, start, lines)
  call appendbufline(buf, '$', '')
  let max_lines = kube#config#get('logs_max_lines')
  let excess = len(getbufline(buf, 1, '$')) - 1 - max_lines
  if max_lines >= 0 && excess > 0
    silent call deletebufline(buf, 1, excess)
  endif
  call s:set_status(a:kbuf, 'Waiting for new logs... (Ctrl+C to stop)')
  for win in at_end
    call win_execute(win, 'call cursor(line("$"), 1)')
  endfor
endfunction
