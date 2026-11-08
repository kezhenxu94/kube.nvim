" The differences between Vim and Neovim: jobs, terminals, marks and virtual
" text (text properties in Vim, extmarks in Neovim), floating windows.

let s:nvim = has('nvim')
let s:next_job = 0

" ---------------------------------------------------------------------------
" Jobs

" Run {cmd} (a list) asynchronously. {opts}:
"   on_exit(code, stdout, stderr)  once the job is done
"   on_stdout(chunk), on_stderr(chunk)  output as it arrives
"   timeout  milliseconds after which the job is killed, with code 124
" Returns the job, {} when it could not be started.
function! kube#compat#run(cmd, opts) abort
  let s:next_job += 1
  let job = {'id': s:next_job, 'done': 0, 'stdout': [], 'stderr': [], 'opts': a:opts, 'timed_out': 0}
  if s:nvim
    try
      let job.job = jobstart(a:cmd, {
            \ 'on_stdout': function('s:nvim_output', [job, 'stdout']),
            \ 'on_stderr': function('s:nvim_output', [job, 'stderr']),
            \ 'on_exit': function('s:nvim_exit', [job]),
            \ 'stdin': 'null',
            \ })
    catch
      let job.job = -1
    endtry
    if job.job <= 0
      call kube#ui#notify('Failed to run ' . a:cmd[0], 'error')
      return {}
    endif
  else
    let job.exited = 0
    let job.closed = 0
    let job.job = job_start(a:cmd, {
          \ 'in_io': 'null',
          \ 'out_mode': 'raw',
          \ 'err_mode': 'raw',
          \ 'out_cb': function('s:vim_output', [job, 'stdout']),
          \ 'err_cb': function('s:vim_output', [job, 'stderr']),
          \ 'exit_cb': function('s:vim_exit', [job]),
          \ 'close_cb': function('s:vim_close', [job]),
          \ })
    if job_status(job.job) ==# 'fail'
      call kube#ui#notify('Failed to run ' . a:cmd[0], 'error')
      return {}
    endif
  endif
  if has_key(a:opts, 'timeout')
    call timer_start(a:opts.timeout, function('s:timeout', [job]))
  endif
  return job
endfunction

function! s:output(job, stream, chunk) abort
  if a:chunk ==# ''
    return
  endif
  call add(a:job[a:stream], a:chunk)
  if has_key(a:job.opts, 'on_' . a:stream)
    call a:job.opts['on_' . a:stream](a:chunk)
  endif
endfunction

function! s:finish(job, code) abort
  if a:job.done
    return
  endif
  let a:job.done = 1
  if has_key(a:job.opts, 'on_exit')
    call a:job.opts.on_exit(a:job.timed_out ? 124 : a:code, join(a:job.stdout, ''), join(a:job.stderr, ''))
  endif
endfunction

function! s:nvim_output(job, stream, id, data, event) abort
  call s:output(a:job, a:stream, join(a:data, "\n"))
endfunction

function! s:nvim_exit(job, id, code, event) abort
  call s:finish(a:job, a:code)
endfunction

function! s:vim_output(job, stream, channel, msg) abort
  call s:output(a:job, a:stream, a:msg)
endfunction

function! s:vim_exit(job, j, status) abort
  let a:job.exited = 1
  let a:job.code = a:status
  if a:job.closed
    call s:finish(a:job, a:status)
  endif
endfunction

function! s:vim_close(job, channel) abort
  let a:job.closed = 1
  if a:job.exited
    call s:finish(a:job, a:job.code)
  endif
endfunction

function! s:timeout(job, timer) abort
  if !a:job.done
    let a:job.timed_out = 1
    call kube#compat#kill(a:job)
  endif
endfunction

" Whether a job, or any of a group of jobs ({'children': [...]}), is running.
function! kube#compat#running(job) abort
  if empty(a:job)
    return 0
  endif
  if has_key(a:job, 'children')
    return len(filter(copy(a:job.children), 'kube#compat#running(v:val)')) > 0
  endif
  return !a:job.done
endfunction

function! kube#compat#kill(job) abort
  if !kube#compat#running(a:job)
    return
  endif
  if has_key(a:job, 'children')
    call map(copy(a:job.children), 'kube#compat#kill(v:val)')
  elseif s:nvim
    call jobstop(a:job.job)
  else
    call job_stop(a:job.job, 'term')
  endif
endfunction

" Run {cmd} synchronously, killed after {timeout} milliseconds.
" Returns [code, stdout], the code is -1 when the job timed out.
function! kube#compat#system(cmd, timeout) abort
  let out = {'stdout': [], 'closed': 0}
  if s:nvim
    try
      let id = jobstart(a:cmd, {'stdin': 'null', 'stdout_buffered': 1,
            \ 'on_stdout': {j, data, e -> extend(out.stdout, [join(data, "\n")])}})
    catch
      return [-1, '']
    endtry
    if id <= 0
      return [-1, '']
    endif
    let code = jobwait([id], a:timeout)[0]
    if code < 0
      call jobstop(id)
      return [-1, '']
    endif
    return [code, join(out.stdout, '')]
  endif
  let job = job_start(a:cmd, {'in_io': 'null', 'err_io': 'null', 'out_mode': 'raw',
        \ 'out_cb': {ch, msg -> add(out.stdout, msg)},
        \ 'close_cb': {ch -> extend(out, {'closed': 1})}})
  let start = reltime()
  while (job_status(job) ==# 'run' || !out.closed) && reltimefloat(reltime(start)) * 1000 < a:timeout
    sleep 5m
  endwhile
  if job_status(job) ==# 'run'
    call job_stop(job, 'kill')
    return [-1, '']
  endif
  return [job_info(job).exitval, join(out.stdout, '')]
endfunction

" ---------------------------------------------------------------------------
" Terminals

" Start {cmd} in a terminal in the current window, in place of the current
" buffer, named {name}: the buffer being read by BufReadCmd.
function! kube#compat#term_start(cmd, name) abort
  let alternate = bufnr('#')
  let buf = bufnr('')
  if s:nvim
    call jobstart(a:cmd, {'term': v:true})
    " jobstart() names the buffer term://..., keep the name so that editing it
    " again finds the shell. :file leaves a buffer with the old name.
    let term_name = bufname('')
    if term_name !=# a:name
      execute 'keepalt file' fnameescape(a:name)
      for info in getbufinfo()
        if info.name ==# term_name
          execute 'bwipeout!' info.bufnr
        endif
      endfor
    endif
  else
    call term_start(a:cmd, {'curwin': 1, 'term_name': a:name})
    " The buffer that was read is replaced by the terminal
    call timer_start(0, {-> execute('silent! bwipeout! ' . buf)})
    if alternate > 0
      let @# = alternate
    endif
  endif
  setlocal nonumber norelativenumber
endfunction

" Start typing in the terminal of the current window.
function! kube#compat#term_enter() abort
  if s:nvim
    startinsert
  endif
endfunction

" ---------------------------------------------------------------------------
" Marks: rows and cells of tables that follow edits, virtual text

" Neovim namespaces by kind of mark
let s:namespaces = {}
" Vim text property types by kind of mark, one per highlight
let s:types = {}
let s:next_mark = 0

function! s:ns(kind) abort
  if !has_key(s:namespaces, a:kind)
    let s:namespaces[a:kind] = nvim_create_namespace('kube_' . a:kind)
  endif
  return s:namespaces[a:kind]
endfunction

" The Vim text property type of {kind} highlighted with {hl}.
function! s:type(kind, hl) abort
  let name = 'kube_' . a:kind . (empty(a:hl) ? '' : '_' . a:hl)
  if empty(prop_type_get(name))
    let opts = {'priority': a:kind ==# 'body' ? -1 : a:kind ==# 'changed' ? 20 : 10}
    if !empty(a:hl)
      let opts.highlight = a:hl
    endif
    " Text typed at either end of a cell, as by `ciw`, stays in the cell
    if a:kind ==# 'cell'
      call extend(opts, {'start_incl': 1, 'end_incl': 1})
    endif
    call prop_type_add(name, opts)
  endif
  let s:types[a:kind] = get(s:types, a:kind, [])
  if index(s:types[a:kind], name) < 0
    call add(s:types[a:kind], name)
  endif
  return name
endfunction

" The Vim text properties of {kind} in the lines {first} to {last}.
function! s:props(buf, kind, first, last) abort
  let types = get(s:types, a:kind, [])
  if empty(types) || !bufloaded(a:buf)
    return []
  endif
  return prop_list(a:first, {'bufnr': a:buf, 'end_lnum': a:last, 'types': types})
endfunction

function! kube#compat#clear(buf, kind) abort
  if !bufloaded(a:buf)
    return
  endif
  if s:nvim
    call nvim_buf_clear_namespace(a:buf, s:ns(a:kind), 0, -1)
  elseif !empty(get(s:types, a:kind, []))
    call prop_remove({'types': s:types[a:kind], 'bufnr': a:buf, 'all': 1})
  endif
endfunction

" Mark the row at {lnum}, highlighted with {hl}. The mark is gone once the
" line is deleted, and back when that is undone. Returns its id.
function! kube#compat#mark_row(buf, lnum, hl) abort
  if s:nvim
    return nvim_buf_set_extmark(a:buf, s:ns('row'), a:lnum - 1, 0, {'invalidate': v:true, 'line_hl_group': a:hl})
  endif
  let s:next_mark += 1
  call prop_add(a:lnum, 1, {'type': s:type('row', ''), 'id': s:next_mark, 'bufnr': a:buf, 'length': 0})
  let length = len(getbufline(a:buf, a:lnum)[0])
  if length > 0
    call prop_add(a:lnum, 1, {'type': s:type('body', a:hl), 'bufnr': a:buf, 'length': length})
  endif
  return s:next_mark
endfunction

" The lines of the marked rows {ids}, by id, 0 for deleted rows.
function! kube#compat#rows(buf, ids) abort
  let lines = {}
  for id in a:ids
    let lines[id] = 0
  endfor
  if !bufloaded(a:buf)
    return lines
  endif
  if s:nvim
    for [id, row, col, details] in nvim_buf_get_extmarks(a:buf, s:ns('row'), 0, -1, {'details': v:true})
      if has_key(lines, id) && !get(details, 'invalid', v:false)
        let lines[id] = row + 1
      endif
    endfor
  else
    for prop in s:props(a:buf, 'row', 1, -1)
      if has_key(lines, prop.id)
        let lines[prop.id] = prop.lnum
      endif
    endfor
  endif
  return lines
endfunction

" The ids of the row marks in the lines {first} to {last}, in order.
function! kube#compat#rows_in(buf, first, last) abort
  if s:nvim
    let marks = nvim_buf_get_extmarks(a:buf, s:ns('row'), [a:first - 1, 0], [a:last - 1, -1], {'details': v:true})
    return map(filter(marks, '!get(v:val[3], "invalid", v:false)'), 'v:val[0]')
  endif
  return map(s:props(a:buf, 'row', a:first, a:last), 'v:val.id')
endfunction

" Mark the cell of the 0-indexed byte range [{start}, {end}) of {lnum},
" highlighted with {hl} unless empty. Returns its id.
function! kube#compat#mark_cell(buf, lnum, start, end, hl) abort
  if s:nvim
    let opts = {'end_col': a:end, 'right_gravity': v:false, 'end_right_gravity': v:true}
    if !empty(a:hl)
      let opts.hl_group = a:hl
    endif
    return nvim_buf_set_extmark(a:buf, s:ns('cell'), a:lnum - 1, a:start, opts)
  endif
  let s:next_mark += 1
  call prop_add(a:lnum, a:start + 1, {'type': s:type('cell', a:hl), 'id': s:next_mark, 'bufnr': a:buf, 'length': a:end - a:start})
  return s:next_mark
endfunction

" The cells of a buffer, by id: [lnum, start, end, hl] with a 0-indexed byte
" range [start, end).
function! kube#compat#cells(buf) abort
  let cells = {}
  if s:nvim
    for [id, row, col, details] in nvim_buf_get_extmarks(a:buf, s:ns('cell'), 0, -1, {'details': v:true})
      let cells[id] = [row + 1, col, details.end_col, get(details, 'hl_group', '')]
    endfor
  else
    for prop in s:props(a:buf, 'cell', 1, -1)
      let hl = prop.type ==# 'kube_cell' ? '' : prop.type[len('kube_cell_'):]
      let cells[prop.id] = [prop.lnum, prop.col - 1, prop.col - 1 + prop.length, hl]
    endfor
  endif
  return cells
endfunction

" The ids of the cells containing the 0-indexed byte {col} of {lnum}.
function! kube#compat#cells_at(buf, lnum, col) abort
  let ids = []
  if s:nvim
    for [id, row, start, details] in nvim_buf_get_extmarks(a:buf, s:ns('cell'), [a:lnum - 1, 0], [a:lnum - 1, -1], {'details': v:true})
      if start <= a:col && a:col < details.end_col && details.end_row == row
        call add(ids, id)
      endif
    endfor
  else
    for prop in s:props(a:buf, 'cell', a:lnum, a:lnum)
      if prop.col - 1 <= a:col && a:col < prop.col - 1 + prop.length
        call add(ids, prop.id)
      endif
    endfor
  endif
  return ids
endfunction

" Highlight the line {lnum} with {hl}, as a mark of {kind}.
function! kube#compat#line_hl(buf, kind, lnum, hl) abort
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns(a:kind), a:lnum - 1, 0, {'line_hl_group': a:hl, 'priority': 200})
    return
  endif
  let length = len(getbufline(a:buf, a:lnum)[0])
  call prop_add(a:lnum, 1, {'type': s:type(a:kind, a:hl), 'bufnr': a:buf, 'length': length})
endfunction

" The lines highlighted as marks of {kind}.
function! kube#compat#highlighted_lines(buf, kind) abort
  if s:nvim
    return map(nvim_buf_get_extmarks(a:buf, s:ns(a:kind), 0, -1, {}), 'v:val[1] + 1')
  endif
  return map(s:props(a:buf, a:kind, 1, -1), 'v:val.lnum')
endfunction

" Show {text} after the line {lnum}, replacing the previous status, none
" when {text} is v:null.
function! kube#compat#set_status(buf, lnum, text, hl) abort
  call kube#compat#clear(a:buf, 'status')
  if !bufloaded(a:buf) || a:text is v:null
    return
  endif
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns('status'), a:lnum - 1, 0, {'virt_text': [[a:text, a:hl]], 'virt_text_pos': 'eol'})
  else
    call prop_add(a:lnum, 0, {'type': s:type('status', a:hl), 'bufnr': a:buf, 'text': a:text, 'text_align': 'after', 'text_padding_left': 1})
  endif
endfunction

" The status: [lnum, text], [] without status.
function! kube#compat#status(buf) abort
  if s:nvim
    let marks = nvim_buf_get_extmarks(a:buf, s:ns('status'), 0, -1, {'details': v:true})
    return empty(marks) ? [] : [marks[0][1] + 1, marks[0][3].virt_text[0][0]]
  endif
  let props = s:props(a:buf, 'status', 1, -1)
  return empty(props) ? [] : [props[0].lnum, props[0].text]
endfunction

" Show {lines} as virtual lines highlighted with {hl}, above or below {lnum}.
function! kube#compat#virt_lines(buf, lnum, lines, hl, above) abort
  if s:nvim
    call nvim_buf_set_extmark(a:buf, s:ns('pending'), a:lnum - 1, 0, {
          \ 'virt_lines': map(copy(a:lines), '[[v:val, a:hl]]'),
          \ 'virt_lines_above': a:above ? v:true : v:false,
          \ })
    " Lines above the first line are only shown as filler of the top line
    if a:above && a:lnum == 1
      for win in win_findbuf(a:buf)
        call win_execute(win, 'if line("w0") == 1 | call winrestview({"topfill": ' . len(a:lines) . '}) | endif')
      endfor
    endif
    return
  endif
  for line in a:lines
    call prop_add(a:lnum, 0, {'type': s:type('pending', a:hl), 'bufnr': a:buf, 'text': line, 'text_align': a:above ? 'above' : 'below'})
  endfor
endfunction

" The virtual lines: [[lnum, lines, above], ...].
function! kube#compat#get_virt_lines(buf) abort
  if s:nvim
    return map(nvim_buf_get_extmarks(a:buf, s:ns('pending'), 0, -1, {'details': v:true}),
          \ '[v:val[1] + 1, map(copy(v:val[3].virt_lines), "v:val[0][0]"), get(v:val[3], "virt_lines_above", v:false) ? 1 : 0]')
  endif
  let result = []
  for prop in s:props(a:buf, 'pending', 1, -1)
    let above = prop.text_align ==# 'above'
    if !empty(result) && result[-1][0] == prop.lnum && result[-1][2] == above
      call add(result[-1][1], prop.text)
    else
      call add(result, [prop.lnum, [prop.text], above])
    endif
  endfor
  return result
endfunction

" Show the header of a table: in the winbar of the windows of the buffer in
" Neovim, above the first line in Vim, which has no winbar.
function! kube#compat#set_header(buf, Winbar) abort
  if s:nvim
    for win in win_findbuf(a:buf)
      call setwinvar(win, '&winbar', a:Winbar(win))
    endfor
    return
  endif
  call kube#compat#clear(a:buf, 'header')
  let kbuf = kube#buffer#get(a:buf)
  if empty(kbuf) || empty(get(kbuf, 'header_row', {})) || !bufloaded(a:buf)
    return
  endif
  let text = kbuf.header_row.formatted . (kbuf.watch ? '  ' . kube#refresh#indicator() : '')
  call prop_add(1, 0, {'type': s:type('header', kbuf.header_row.highlight), 'bufnr': a:buf, 'text': text, 'text_align': 'above'})
endfunction

" The header shown for the buffer in the window {win}.
function! kube#compat#header(buf, win) abort
  if s:nvim
    return getwinvar(a:win, '&winbar')
  endif
  let props = s:props(a:buf, 'header', 1, 1)
  return empty(props) ? '' : props[0].text
endfunction

" ---------------------------------------------------------------------------
" Floating windows

" Show {lines} in a floating window: entered with {enter}, closed with q,
" <Esc> or {close_keys}; else closed when the cursor moves, like a hover.
" Returns the window id.
function! kube#compat#float(lines, opts) abort
  let width = max(map(copy(a:lines), 'strdisplaywidth(v:val)') + [1])
  let title = get(a:opts, 'title', '')
  if s:nvim
    let buf = nvim_create_buf(v:false, v:true)
    call nvim_buf_set_lines(buf, 0, -1, v:false, a:lines)
    call setbufvar(buf, '&modifiable', 0)
    call setbufvar(buf, '&bufhidden', 'wipe')
    let enter = get(a:opts, 'enter', 0)
    let config = {
          \ 'width': min([width + 2, &columns - 4]),
          \ 'height': max([1, min([len(a:lines), &lines - 4])]),
          \ 'style': 'minimal',
          \ 'border': 'rounded',
          \ }
    if enter
      call extend(config, {'relative': 'editor',
            \ 'row': max([0, (&lines - len(a:lines)) / 2]), 'col': max([0, (&columns - width) / 2])})
    else
      call extend(config, {'relative': 'cursor', 'row': 1, 'col': 0})
    endif
    if !empty(title)
      call extend(config, {'title': title, 'title_pos': 'center'})
    endif
    let win = nvim_open_win(buf, enter ? v:true : v:false, config)
    if enter
      for lhs in ['q', '<Esc>'] + get(a:opts, 'close_keys', [])
        call win_execute(win, 'nnoremap <buffer> <nowait> <silent> ' . lhs . ' <Cmd>close<CR>')
      endfor
      call win_execute(win, 'autocmd WinLeave <buffer> ++once silent! close')
    else
      execute 'autocmd CursorMoved,BufLeave,InsertEnter <buffer> ++once call s:close_float(' . win . ')'
    endif
    return win
  endif
  let options = {
        \ 'border': [], 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'], 'padding': [0, 1, 0, 1], 'title': title,
        \ 'maxheight': &lines - 4, 'maxwidth': &columns - 4, 'scrollbar': 1,
        \ }
  if get(a:opts, 'enter', 0)
    let options.filter = function('s:popup_filter', [['q'] + get(a:opts, 'close_keys', [])])
    let options.mapping = 0
    let options.pos = 'center'
    return popup_create(a:lines, options)
  endif
  return popup_atcursor(a:lines, options)
endfunction

function! s:close_float(win) abort
  if nvim_win_is_valid(a:win)
    call nvim_win_close(a:win, v:true)
  endif
endfunction

" Close keys of several characters, e.g. g?, close on their last one.
function! s:popup_filter(close_keys, win, key) abort
  if a:key ==# "\<Esc>" || index(map(copy(a:close_keys), 'v:val[-1:]'), a:key) >= 0
    call popup_close(a:win)
  elseif index(['j', "\<Down>", "\<C-e>"], a:key) >= 0
    call win_execute(a:win, "normal! \<C-e>")
  elseif index(['k', "\<Up>", "\<C-y>"], a:key) >= 0
    call win_execute(a:win, "normal! \<C-y>")
  endif
  return 1
endfunction

" The floating windows: [[winid, lines], ...].
function! kube#compat#floats() abort
  if s:nvim
    let wins = filter(nvim_list_wins(), 'nvim_win_get_config(v:val).relative !=# ""')
  else
    let wins = popup_list()
  endif
  return map(wins, '[v:val, getbufline(winbufnr(v:val), 1, "$")]')
endfunction

function! kube#compat#close_float(win) abort
  if s:nvim
    call nvim_win_close(a:win, v:true)
  else
    call popup_close(a:win)
  endif
endfunction

" ---------------------------------------------------------------------------
" Miscellaneous

" Where kube.nvim keeps its state, e.g. the context of :Kube context.
function! kube#compat#state_file(name) abort
  if s:nvim
    let dir = stdpath('state')
  else
    let dir = (empty($XDG_STATE_HOME) ? expand('~/.local/state') : $XDG_STATE_HOME) . '/vim'
  endif
  return dir . '/' . a:name
endfunction

" The groups the highlights link to by default.
function! kube#compat#highlight_links() abort
  let warn = s:nvim ? 'DiagnosticWarn' : 'WarningMsg'
  let error = s:nvim ? 'DiagnosticError' : 'ErrorMsg'
  return {
        \ 'KubeBody': 'Normal',
        \ 'KubePending': warn,
        \ 'KubeRunning': 'Normal',
        \ 'KubeFailed': error,
        \ 'KubeSucceeded': 'Comment',
        \ 'KubeUnknown': 'Comment',
        \ 'KubeHeader': 'Title',
        \ 'KubeDeleted': 'DiffDelete',
        \ 'KubeChanged': 'DiffChange',
        \ 'KubeEditable': 'Identifier',
        \ 'KubeSignError': s:nvim ? 'DiagnosticSignError' : 'ErrorMsg',
        \ 'KubeSignWarn': s:nvim ? 'DiagnosticSignWarn' : 'WarningMsg',
        \ 'KubeSignInfo': s:nvim ? 'DiagnosticSignInfo' : 'Comment',
        \ }
endfunction

" Jumps to what the cell under the cursor refers to with <C-]>, like tags:
" 'tagfunc' in Neovim. Vim refuses tags of URLs (E1576): the keys are mapped
" and the jumps pushed on the tag stack instead, so that <C-t> goes back.
function! kube#compat#setup_tags(buf) abort
  if s:nvim
    call setbufvar(a:buf, '&tagfunc', 'kube#navigation#tagfunc')
    return
  endif
  nnoremap <buffer> <silent> <C-]> :<C-u>call kube#compat#tag_jump(0)<CR>
  nnoremap <buffer> <silent> <C-w>] :<C-u>call kube#compat#tag_jump(1)<CR>
  nnoremap <buffer> <silent> <C-w><C-]> :<C-u>call kube#compat#tag_jump(1)<CR>
endfunction

function! kube#compat#tag_jump(split) abort
  let target = kube#navigation#tag_target(kube#buffer#get(bufnr('')), line('.'), col('.') - 1)
  if empty(target)
    echoerr 'E426: Tag not found: ' . expand('<cword>')
    return
  endif
  let item = {'bufnr': bufnr(''), 'from': [bufnr(''), line('.'), col('.'), 0], 'tagname': expand('<cword>')}
  if a:split
    split
  endif
  call settagstack(win_getid(), {'items': [item]}, 't')
  call kube#utils#edit(target)
endfunction
