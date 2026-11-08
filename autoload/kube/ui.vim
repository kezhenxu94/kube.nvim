" Messages and prompts.

" Show {msg}, {level} is 'info' (the default), 'warn' or 'error'.
function! kube#ui#notify(msg, ...) abort
  let level = get(a:, 1, 'info')
  execute 'echohl' get({'error': 'ErrorMsg', 'warn': 'WarningMsg'}, level, 'None')
  for line in split(a:msg, "\n")
    echomsg line
  endfor
  echohl None
endfunction

" Prompts are deferred to a timer: Vim does not read the answer of a prompt
" in a job callback.

" Select one of {items}, {opts}: prompt, format_item (a funcref).
" Calls {Callback}(item, index) with the 1-based index, v:null when cancelled.
function! kube#ui#select(items, opts, Callback) abort
  call timer_start(0, function('s:select', [a:items, a:opts, a:Callback]))
endfunction

function! s:select(items, opts, Callback, timer) abort
  let lines = split(get(a:opts, 'prompt', 'Select:'), "\n")
  let i = 0
  for item in a:items
    let i += 1
    call add(lines, printf('%d: %s', i, has_key(a:opts, 'format_item') ? a:opts.format_item(item) : item))
  endfor
  redraw
  let choice = inputlist(lines)
  if choice < 1 || choice > len(a:items)
    call a:Callback(v:null, v:null)
    return
  endif
  call a:Callback(a:items[choice - 1], choice)
endfunction

" Ask for a value, {opts}: prompt, default.
" Calls {Callback}(value), v:null when cancelled or empty.
function! kube#ui#input(opts, Callback) abort
  call timer_start(0, function('s:input', [a:opts, a:Callback]))
endfunction

function! s:input(opts, Callback, timer) abort
  let value = input(get(a:opts, 'prompt', ''), get(a:opts, 'default', ''))
  call a:Callback(empty(value) ? v:null : value)
endfunction

" Ask Yes or No, calls {Callback}(confirmed).
function! kube#ui#confirm(prompt, Callback) abort
  call kube#ui#select(['Yes', 'No'], {'prompt': a:prompt}, function('s:confirmed', [a:Callback]))
endfunction

function! s:confirmed(Callback, choice, index) abort
  call a:Callback(type(a:choice) == v:t_string && a:choice ==# 'Yes')
endfunction

" Open {url}, e.g. in the browser.
function! kube#ui#open(url) abort
  execute 'Open' fnameescape(a:url)
endfunction
