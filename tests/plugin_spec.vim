" The plugin is loaded by the runner like at startup
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')

call t#describe('plugin/kube.vim')
call t#after_each(function('t#restore_stubs'))

function! s:test_command() abort
  call assert_equal(2, exists(':Kube'))
endfunction
call t#it('defines :Kube', function('s:test_command'))

function! s:test_opens() abort
  call t#reset_kubectl()
  call t#respond('*config current-context*', {'stdout': "ctx-a\n"})
  call t#respond('*get pods -o json*', {'fixture': 'pods.json'})
  call t#capture_notify()
  call t#open('kube://pods')
  call assert_equal(2, len(t#lines()))
  call t#clean_buffers()
endfunction
call t#it('opens kube buffers without configuration', function('s:test_opens'))

function! s:test_loaded_once() abort
  unlet g:loaded_kube
  runtime plugin/kube.vim
  runtime plugin/kube.vim
  call assert_equal(1, len(filter(split(execute('autocmd resource_kube BufReadCmd'), "\n"), 'v:val =~# "resource#buffer#on_read"')))
endfunction
call t#it('is loaded once', function('s:test_loaded_once'))

function! s:test_highlight_links() abort
  colorscheme default
  call assert_match('links to ' . (has('nvim') ? 'DiagnosticError' : 'ErrorMsg'), execute('highlight KubeFailed'))
  highlight KubeFailed guifg=#654321
  call resource#highlights()
  call assert_match('guifg=#654321', execute('highlight KubeFailed'))
endfunction
call t#it('links highlights to the colorscheme unless defined', function('s:test_highlight_links'))

function! s:test_highlight_overrides() abort
  let g:kube_highlights = {'KubeHeader': 'guifg=#123456'}
  try
    colorscheme default
    call assert_match('guifg=#123456', execute('highlight KubeHeader'))
  finally
    unlet g:kube_highlights
  endtry
endfunction
call t#it('keeps highlight overrides across colorschemes', function('s:test_highlight_overrides'))

call t#describe('help')

function! s:test_help_tags() abort
  let doc = tempname()
  call mkdir(doc . '/doc', 'p')
  call writefile(readfile(s:root . '/doc/kube.txt'), doc . '/doc/kube.txt')
  execute 'helptags' fnameescape(doc . '/doc')
  execute 'set runtimepath+=' . fnameescape(doc)
  help kube.nvim
  call assert_equal('kube.txt', expand('%:t'))
  help kube-jump
  call assert_equal('kube.txt', expand('%:t'))
  close
endfunction
call t#it('has valid tags', function('s:test_help_tags'))
