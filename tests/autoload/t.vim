" Test helpers, see tests/runner.vim. Assertions are Vim's assert_*().

let s:dir = $KUBE_TEST_DIR
let s:fixtures = fnamemodify(expand('<sfile>:p'), ':h:h') . '/fixtures'
let s:suite = {'name': '', 'before': [], 'after': []}
let s:file_hooks = {'before': [], 'after': []}

" Group the tests registered next under {name}, with their own hooks.
function! t#describe(name) abort
  let s:suite = {'name': a:name, 'before': [], 'after': []}
endfunction

function! t#before_each(Fn) abort
  call add(empty(s:suite.name) ? s:file_hooks.before : s:suite.before, a:Fn)
endfunction

function! t#after_each(Fn) abort
  call insert(empty(s:suite.name) ? s:file_hooks.after : s:suite.after, a:Fn)
endfunction

function! t#it(name, Fn) abort
  call add(g:t_tests, {
        \ 'name': empty(s:suite.name) ? a:name : s:suite.name . ' > ' . a:name,
        \ 'before': s:file_hooks.before + s:suite.before,
        \ 'after': s:suite.after + s:file_hooks.after,
        \ 'fn': a:Fn,
        \ })
endfunction

" Skip the running test.
function! t#skip(reason) abort
  throw 'skip: ' . a:reason
endfunction

function! t#fixture(name) abort
  return join(readfile(s:fixtures . '/' . a:name), "\n")
endfunction

function! t#json(name) abort
  return json_decode(t#fixture(a:name))
endfunction

" The fake kubectl (tests/bin/kubectl) replies to calls whose arguments
" match the shell glob {pattern}, later rules take precedence. {opts}: stdout,
" stderr, code, fixture, script.
let s:rules = []

function! s:write_rules() abort
  call writefile(map(copy(s:rules), 'v:val.pattern . "\t" . v:val.script'), s:dir . '/rules')
endfunction

function! t#respond(pattern, opts) abort
  let base = printf('%s/rule%d', s:dir, len(s:rules) + 1)
  let script = get(a:opts, 'script', '')
  if empty(script)
    let stdout = has_key(a:opts, 'fixture') ? t#fixture(a:opts.fixture) : get(a:opts, 'stdout', '')
    call writefile(split(stdout, "\n", 1), base . '.out', 'b')
    call writefile(split(get(a:opts, 'stderr', ''), "\n", 1), base . '.err', 'b')
    let script = printf("cat '%s.out'; cat '%s.err' >&2; exit %d", base, base, get(a:opts, 'code', 0))
  endif
  call writefile([script], base . '.sh')
  call insert(s:rules, {'pattern': a:pattern, 'script': base . '.sh'})
  call s:write_rules()
endfunction

" The arguments of each kubectl call since the last reset, {raw} with
" --request-timeout.
function! t#calls(...) abort
  let file = s:dir . (get(a:, 1, 0) ? '/raw_calls' : '/calls')
  return filereadable(file) ? readfile(file) : []
endfunction

" The calls matching the regexp {pattern}.
function! t#calls_matching(pattern) abort
  return filter(t#calls(), 'v:val =~# a:pattern')
endfunction

function! t#reset_kubectl() abort
  let s:rules = []
  call s:write_rules()
  call delete(s:dir . '/calls')
  call delete(s:dir . '/raw_calls')
endfunction

" Wait until the expression or funcref {Condition} is true, fail after
" {timeout} milliseconds (5000 by default).
function! t#wait_for(Condition, what, ...) abort
  let timeout = get(a:, 1, 5000)
  let start = reltime()
  while 1
    if type(a:Condition) == v:t_func ? a:Condition() : eval(a:Condition)
      return
    endif
    if reltimefloat(reltime(start)) * 1000 > timeout
      throw 'timed out waiting for ' . a:what
    endif
    sleep 10m
  endwhile
endfunction

function! t#wait(ms) abort
  execute 'sleep' a:ms . 'm'
endfunction

" Answer the prompts: {Select}(items, opts) returns the chosen item (v:null
" to cancel), {input} is the answer to inputs.
" Stubs replace functions of autoload/resource.vim and autoload/kube/ui.vim,
" loaded first so that they do not replace them later.
function! s:load_ui() abort
  if !exists('*resource#confirm')
    runtime autoload/resource.vim
  endif
  if !exists('*kube#ui#open')
    runtime autoload/kube/ui.vim
  endif
endfunction

function! t#answer_prompts(Select, input) abort
  call s:load_ui()
  let g:T_select = a:Select
  let g:t_input = a:input
  function! resource#select(items, opts, Callback) abort
    let choice = g:T_select is v:null ? v:null : g:T_select(a:items, a:opts)
    let index = 0
    for i in range(len(a:items))
      if a:items[i] is choice
        let index = i + 1
      endif
    endfor
    call a:Callback(index ? choice : v:null, index ? index : v:null)
  endfunction
  function! resource#input(opts, Callback) abort
    call a:Callback(g:t_input)
  endfunction
endfunction

" Capture the notifications: a list of {msg, level}, also in g:t_messages.
function! t#capture_notify() abort
  call s:load_ui()
  let g:t_messages = []
  function! resource#notify(msg, ...) abort
    call add(g:t_messages, {'msg': a:msg, 'level': get(a:, 1, 'info')})
  endfunction
  return g:t_messages
endfunction

" Capture the URLs opened, in g:t_opened.
function! t#capture_open() abort
  call s:load_ui()
  let g:t_opened = []
  function! kube#ui#open(url) abort
    call add(g:t_opened, a:url)
  endfunction
endfunction

" Restore the stubbed prompts, notifications and opener.
function! t#restore_stubs() abort
  runtime autoload/resource.vim
  runtime autoload/kube/ui.vim
endfunction

" Kill the kube jobs and wipe every buffer, leaving an empty one.
function! t#clean_buffers() abort
  silent! %bwipeout!
  call t#wait_for({-> empty(resource#buffers())}, 'kube buffers to be cleaned up')
endfunction

function! t#lines(...) abort
  return getbufline(get(a:, 1, bufnr('')), 1, '$')
endfunction

" The status shown after a line, v:null if none.
function! t#status(...) abort
  let status = resource#compat#status(get(a:, 1, bufnr('')))
  return empty(status) ? v:null : status[1]
endfunction

function! t#kbuf() abort
  return resource#get(bufnr(''))
endfunction

" Wait for the current kube buffer to finish loading.
function! t#wait_loaded(...) abort
  let buf = bufnr('')
  call t#wait_for({-> !empty(resource#get(buf)) && !resource#loading(buf)}, 'buffer to load', get(a:, 1, 5000))
  " Let the timers of the render run
  sleep 20m
endfunction

" Edit {name} and wait for it to load.
function! t#open(name, ...) abort
  execute 'edit' fnameescape(a:name)
  call t#wait_loaded(get(a:, 1, 5000))
endfunction

function! t#wait_buf_name(name, ...) abort
  call t#wait_for({-> bufname('') ==# a:name}, 'buffer ' . a:name . ', current: ' . bufname(''), get(a:, 1, 5000))
endfunction

function! t#wait_call(pattern, ...) abort
  let minimum = get(a:, 1, 1)
  call t#wait_for({-> len(t#calls_matching(a:pattern)) >= minimum}, 'kubectl call matching ' . a:pattern)
endfunction

" Move the cursor to the first occurrence of {text} and type {keys}.
function! t#press_on(text, keys) abort
  call cursor(1, 1)
  let lnum = search('\V' . escape(a:text, '\'), 'cW')
  call assert_true(lnum > 0, 'line not found: ' . a:text)
  if !empty(a:keys)
    call t#press(a:keys)
  endif
endfunction

" Type {keys}, with mappings.
function! t#press(keys) abort
  call feedkeys(a:keys, 'mx')
endfunction

" Answer prompts with the first item, returns the list of their prompts.
function! t#prompts() abort
  let g:t_prompts = []
  call t#answer_prompts({items, opts -> [add(g:t_prompts, get(opts, 'prompt', '')), items[0]][1]}, v:null)
  return g:t_prompts
endfunction

" Answer Yes to confirmations, else the first item.
function! t#answer_yes(...) abort
  call t#answer_prompts({items, opts -> index(items, 'Yes') >= 0 ? 'Yes' : items[0]}, get(a:, 1, v:null))
endfunction

" Run the operation {title} on the cursor line or the lines {first} to {last}:
" returns the titles offered.
function! t#operation(title, ...) abort
  let kbuf = t#kbuf()
  let [first, last] = a:0 ? [a:1, a:2] : [line('.'), line('.')]
  let operations = kube#operations#for_items(kbuf, resource#items(kbuf, first, last))
  let titles = map(copy(operations), 'v:val.title')
  call assert_notequal(-1, index(titles, a:title), a:title . ' not in ' . string(titles))
  for operation in operations
    if operation.title ==# a:title
      call operation.run()
    endif
  endfor
  return titles
endfunction

" The floating window showing {text}, waits for it.
function! t#wait_float(text) abort
  call t#wait_for(function('s:float_with', [a:text]), 'a float with ' . a:text)
  return s:float_with(a:text)
endfunction

function! s:float_with(text) abort
  for [win, lines] in resource#compat#floats()
    if stridx(join(lines, "\n"), a:text) >= 0
      return win
    endif
  endfor
  return 0
endfunction

" The diagnostics of the current buffer: [[lnum, severity, message]].
function! t#diagnostics() abort
  let result = []
  for lnum in resource#table#diagnostic_lines(bufnr(''))
    for diagnostic in resource#table#diagnostics(bufnr(''), lnum)
      call add(result, [lnum, diagnostic.severity, diagnostic.message])
    endfor
  endfor
  return result
endfunction

" Assert that {cmd} fails with {error}, which the runner then ignores.
function! t#fails(cmd, error) abort
  call assert_fails(a:cmd, a:error)
  messages clear
endfunction
