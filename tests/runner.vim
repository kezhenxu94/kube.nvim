" Minimal test runner, runs the spec g:spec in Vim or Neovim:
"   vim -Nu NONE -i NONE --not-a-term --cmd "let g:spec = 'tests/x_spec.vim'" -S tests/runner.vim
"   nvim --headless -u NONE -i NONE --cmd "let g:spec = 'tests/x_spec.vim'" -S tests/runner.vim
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root) . ',' . fnameescape(s:root . '/tests')
" Neovim's defaults, which the tests assume
set hidden nomore
" The end-to-end tests use the real kubectl against a cluster
if empty($KUBE_E2E_CONTEXT)
  let $PATH = s:root . '/tests/bin:' . $PATH
endif
let $KUBE_TEST_DIR = tempname()
call mkdir($KUBE_TEST_DIR, 'p')

" Loaded like at startup
runtime plugin/kube.vim

let g:t_tests = []
execute 'source' fnameescape(g:spec)

" The results, in $KUBE_TEST_OUT if set: Vim's screen is on stdout
function! s:out(line) abort
  call writefile([a:line], empty($KUBE_TEST_OUT) ? '/dev/stdout' : $KUBE_TEST_OUT, 'a')
endfunction

let s:failed = 0
let s:skipped = 0
for s:test in g:t_tests
  let v:errors = []
  let s:skip = ''
  try
    for s:Hook in s:test.before
      call s:Hook()
    endfor
    call s:test.fn()
  catch /^skip: /
    let s:skip = v:exception[len('skip: '):]
  catch
    call add(v:errors, v:exception . "\n" . v:throwpoint)
  endtry
  " Errors outside of assertions, e.g. in callbacks
  call extend(v:errors, filter(split(execute('messages'), "\n"), 'v:val =~# "^E\\d\\+:"'))
  messages clear
  for s:Hook in s:test.after
    try
      call s:Hook()
    catch
      call add(v:errors, 'after_each: ' . v:exception . "\n" . v:throwpoint)
    endtry
  endfor
  if !empty(s:skip)
    let s:skipped += 1
    call s:out('  skip ' . s:test.name . ': ' . s:skip)
  elseif empty(v:errors)
    call s:out('  ok   ' . s:test.name)
  else
    let s:failed += 1
    call s:out('  FAIL ' . s:test.name)
    for s:error in v:errors
      call s:out('       ' . substitute(s:error, "\n", "\n       ", 'g'))
    endfor
  endif
endfor

call s:out(printf('%s (%s): %d passed, %d failed, %d skipped', g:spec, has('nvim') ? 'nvim' : 'vim',
      \ len(g:t_tests) - s:failed - s:skipped, s:failed, s:skipped))
call s:out('')
call delete($KUBE_TEST_DIR, 'rf')
" Written when all tests passed, the exit code is that of a crash too
if s:failed == 0 && !empty($KUBE_TEST_RESULT)
  call writefile(['ok'], $KUBE_TEST_RESULT)
endif
execute 'cquit' (s:failed > 0)
