" Open {url}, e.g. in the browser.
function! kube#ui#open(url) abort
  execute 'Open' fnameescape(a:url)
endfunction
