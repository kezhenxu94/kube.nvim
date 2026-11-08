" Lists of resources as tables: aligned columns, rows and cells that follow
" edits, deleted rows shown until written.

let s:MAX_COLUMN_WIDTH = 99
let s:COLUMN_SEPARATOR = '  '
" Columns that change on every reload, not worth showing as a change
let s:VOLATILE_COLUMNS = ['AGE', 'LAST SEEN', 'CPU', 'MEMORY']
let s:FLASH_DURATION = 1500
let s:SEVERITIES = {'error': 'KubeSignError', 'warn': 'KubeSignWarn', 'info': 'KubeSignInfo'}

" Identity of the item of a row that survives reloads, so that the cursor can
" stay on the same row.
function! s:row_identity(item) abort
  if type(a:item) != v:t_dict
    return ''
  endif
  if has_key(a:item, 'metadata')
    return join([get(a:item, 'kind', ''), kube#utils#get(a:item.metadata, 'namespace', ''), kube#utils#get(a:item.metadata, 'name', '')], '/')
  endif
  if has_key(a:item, 'local_port')
    return a:item.id . ':' . a:item.local_port
  endif
  " Helm releases of the same name in different namespaces
  if has_key(a:item, 'namespace')
    return a:item.namespace . '/' . a:item.name
  endif
  return get(a:item, 'name', '')
endfunction

" The item of the row at {lnum}, v:null if none.
function! kube#table#item_at(kbuf, lnum) abort
  let ids = kube#compat#rows_in(a:kbuf.bufnr, a:lnum, a:lnum)
  let row = empty(ids) ? {} : get(a:kbuf.rows, ids[0], {})
  return get(row, 'item', v:null)
endfunction

" The items of the rows in the lines {first} to {last}.
function! kube#table#items_in_rows(kbuf, first, last) abort
  let items = []
  for id in kube#compat#rows_in(a:kbuf.bufnr, a:first, a:last)
    if has_key(a:kbuf.rows, id)
      call add(items, a:kbuf.rows[id].item)
    endif
  endfor
  return items
endfunction

" The lines of the rows by mark id, 0 for deleted rows.
function! kube#table#row_lines(kbuf) abort
  return kube#compat#rows(a:kbuf.bufnr, keys(a:kbuf.rows))
endfunction

" Remember the row under the cursor of every window showing the buffer.
function! s:save_cursors(kbuf) abort
  let saved = []
  for win in win_findbuf(a:kbuf.bufnr)
    let [lnum, col] = getcurpos(win)[1:2]
    call add(saved, {'win': win, 'identity': s:row_identity(kube#table#item_at(a:kbuf, lnum)), 'cursor': [lnum, col]})
  endfor
  return saved
endfunction

" Move the cursors back to the rows of the same items, or keep the line when
" the item is gone.
function! s:restore_cursors(saved, rows) abort
  for entry in a:saved
    let lnum = min([entry.cursor[0], max([len(a:rows), 1])])
    if !empty(entry.identity)
      let i = 0
      for row in a:rows
        let i += 1
        if s:row_identity(row.raw) ==# entry.identity
          let lnum = i
          break
        endif
      endfor
    endif
    call win_execute(entry.win, printf('call cursor(%d, %d)', lnum, entry.cursor[1]))
  endfor
endfunction

function! s:row_signature(headers, cells) abort
  let values = []
  for i in range(len(a:headers))
    if index(s:VOLATILE_COLUMNS, a:headers[i]) < 0
      call add(values, get(a:cells, i, ''))
    endif
  endfor
  return join(values, "\x01")
endfunction

" The signatures of the rendered rows by identity, v:null before the first
" render.
function! s:signatures(kbuf) abort
  if empty(a:kbuf.rows)
    return v:null
  endif
  let result = {}
  for row in values(a:kbuf.rows)
    let identity = s:row_identity(row.item)
    if !empty(identity)
      let result[identity] = row.signature
    endif
  endfor
  return result
endfunction

" Highlight the lines {lnums} for a moment.
function! s:flash(kbuf, lnums) abort
  for lnum in a:lnums
    call kube#compat#line_hl(a:kbuf.bufnr, 'changed', lnum, 'KubeChanged')
  endfor
  if empty(a:lnums)
    return
  endif
  let a:kbuf.flash_generation = get(a:kbuf, 'flash_generation', 0) + 1
  call timer_start(s:FLASH_DURATION, function('s:unflash', [a:kbuf, a:kbuf.flash_generation]))
endfunction

function! s:unflash(kbuf, generation, timer) abort
  " A later reload flashes its own rows
  if a:kbuf.flash_generation == a:generation && bufloaded(a:kbuf.bufnr)
    call kube#compat#clear(a:kbuf.bufnr, 'changed')
  endif
endfunction

function! kube#table#formatter_for(kbuf) abort
  return kube#format#get(empty(a:kbuf.subresource_kind) ? a:kbuf.resource_kind : a:kbuf.subresource_kind)
endfunction

" Contexts whose cluster has no metrics API, not asked again
let s:metrics_unavailable = {}

" CPU and memory usage by namespace/name, from kubectl top --no-headers.
function! s:parse_metrics(output, kind, namespace) abort
  let metrics = {}
  for line in split(a:output, "\n")
    let fields = split(line)
    if a:kind ==# 'nodes'
      " NAME CPU(cores) CPU(%) MEMORY(bytes) MEMORY(%)
      let metrics['/' . fields[0]] = [fields[1], fields[3]]
    elseif tolower(a:namespace) ==# 'all'
      let metrics[fields[0] . '/' . fields[1]] = [fields[2], fields[3]]
    else
      let metrics[a:namespace . '/' . fields[0]] = [fields[1], fields[2]]
    endif
  endfor
  return metrics
endfunction

" Load a list with kubectl get, and the metrics of its resources when they have.
function! kube#table#load(kbuf) abort
  let k = a:kbuf
  let formatter = kube#table#formatter_for(k)
  let kind = empty(k.resource_name) ? get(formatter, 'metrics', '') : ''
  let with_metrics = !empty(kind) && !has_key(s:metrics_unavailable, k.context)

  " Render once the resources and, if asked, their metrics are loaded
  let state = {'kbuf': k, 'formatter': formatter, 'pending': with_metrics ? 2 : 1, 'data': v:null, 'metrics': v:null}
  let job = kube#buffer#track(k, kube#kubectl#get(k.context, k.resource_kind, k.resource_name, k.namespace, k.params,
        \ function('s:on_data', [state]), kube#buffer#on_error(k)))
  if empty(job) || !with_metrics
    return job
  endif
  let top = kube#buffer#track(k, kube#kubectl#top(k.context, kind, k.namespace, get(k.params, 'selector', ''),
        \ function('s:on_metrics', [state, kind]), function('s:on_metrics_error', [k.context])))
  if empty(top)
    call s:loaded(state)
    return job
  endif
  return {'children': [job, top]}
endfunction

function! s:loaded(state) abort
  let a:state.pending -= 1
  if a:state.pending == 0 && a:state.data isnot v:null && bufloaded(a:state.kbuf.bufnr)
    call kube#table#render(a:state.kbuf, a:state.formatter, a:state.data, a:state.metrics)
  endif
endfunction

function! s:on_data(state, result) abort
  " The jobs of an unloaded buffer are killed, ending without output
  if a:result isnot v:null && bufloaded(a:state.kbuf.bufnr)
    let a:state.data = json_decode(a:result)
  endif
  call s:loaded(a:state)
endfunction

function! s:on_metrics(state, kind, result) abort
  if a:result isnot v:null
    let a:state.metrics = s:parse_metrics(a:result, a:kind, a:state.kbuf.namespace)
  endif
  call s:loaded(a:state)
endfunction

function! s:on_metrics_error(context, err) abort
  if stridx(a:err, 'Metrics API not available') >= 0
    let s:metrics_unavailable[a:context] = 1
  endif
endfunction

" Insert the CPU and memory usage columns before AGE, returns the headers.
function! s:add_metrics(headers, rows, metrics) abort
  let at = index(a:headers, 'AGE')
  let at = at < 0 ? len(a:headers) : at
  for row in a:rows
    let usage = get(a:metrics, kube#utils#get(row.item.metadata, 'namespace', '') . '/' . row.item.metadata.name, ['', ''])
    call extend(row.row, usage, at)
  endfor
  return extend(copy(a:headers), ['CPU', 'MEMORY'], at)
endfunction

" Render the rows of {data} as a table, keeping the cursors on the same rows.
" {metrics}: the usage of the resources, adds CPU and MEMORY columns, or v:null.
function! kube#table#render(kbuf, formatter, data, metrics) abort
  let k = a:kbuf
  let buf = k.bufnr
  " Edits made while a background reload was running win over the reload
  if k.silent && getbufvar(buf, '&modified')
    return
  endif
  let headers = a:formatter.headers
  let cursors = s:save_cursors(k)
  let previous = s:signatures(k)

  for kind in ['row', 'body', 'cell', 'pending', 'changed']
    call kube#compat#clear(buf, kind)
  endfor
  call sign_unplace('kube_diagnostics', {'buffer': buf})
  let k.rows = {}
  let k.cells = {}
  let k.diagnostics = {}
  let k.data = a:data

  let rows = a:formatter.fn(a:data, k)
  if a:metrics isnot v:null
    let headers = s:add_metrics(headers, rows, a:metrics)
  endif

  call kube#buffer#setup(k)
  let [header_row, formatted_rows] = kube#table#format_table(headers, rows)[0:1]
  let k.header_row = header_row
  call kube#buffer#set_lines(k, map(copy(formatted_rows), 'v:val.formatted'), 1)
  call s:restore_cursors(cursors, formatted_rows)
  if empty(formatted_rows)
    call kube#buffer#set_status(k, get(a:formatter, 'empty', 'No resources found'), 'Comment')
  endif

  let editable = get(a:formatter, 'editable', {})
  let changed = []
  let lnum = 0
  for row in formatted_rows
    let lnum += 1
    let row_mark = v:null
    if row.raw isnot v:null
      let row_mark = kube#compat#mark_row(buf, lnum, 'KubeBody')
      let signature = s:row_signature(headers, row.cells)
      let k.rows[row_mark] = {'item': row.raw, 'line': row.formatted, 'signature': signature}
      let identity = s:row_identity(row.raw)
      let before = previous is v:null ? signature : get(previous, identity, v:null)
      if !empty(identity) && (type(before) != v:t_string || before !=# signature)
        call add(changed, lnum)
      endif
    endif

    let i = 0
    for [start, end] in row.ranges
      let header = headers[i]
      let hl = get(row.highlights, header, has_key(editable, header) ? 'KubeEditable' : '')
      let id = kube#compat#mark_cell(buf, lnum, start, end, hl)
      let k.cells[id] = {'item': row.raw, 'column': header, 'text': trim(strpart(row.formatted, start, end - start)), 'row': row_mark}
      let i += 1
    endfor

    for diagnostic in row.diagnostics
      let id = sign_place(0, 'kube_diagnostics', s:SEVERITIES[diagnostic.severity], buf, {'lnum': lnum})
      let k.diagnostics[id] = diagnostic
    endfor
  endfor

  " After the signs, which may change the width of the sign column the header
  " is aligned with
  if !empty(win_findbuf(buf))
    redraw
  endif
  call kube#utils#update_winbar(k)
  " Only reloads of a watched list: a reload asked for shows the changes it
  " was asked for
  if k.silent
    call s:flash(k, changed)
  endif
endfunction

" Show the rows deleted from the buffer, which :w deletes, where they were:
" above the next row, below the last line when no row is left after them.
function! kube#table#show_pending(kbuf) abort
  let buf = a:kbuf.bufnr
  call kube#compat#clear(buf, 'pending')
  let lines = kube#table#row_lines(a:kbuf)
  " Marks are created in the order of the rows
  let ids = sort(map(keys(lines), 'str2nr(v:val)'), 'n')
  let groups = []
  let deleted = []
  for id in ids
    if lines[id] == 0
      call add(deleted, a:kbuf.rows[id].line)
    elseif !empty(deleted)
      call add(groups, [lines[id], deleted, 1])
      let deleted = []
    endif
  endfor
  if !empty(deleted)
    call add(groups, [len(getbufline(buf, 1, '$')), deleted, 0])
  endif
  for [lnum, rows, above] in groups
    call kube#compat#virt_lines(buf, lnum, rows, 'KubeDeleted', above)
  endfor
  " Vim shows the header above the first line, which may have been deleted
  call kube#utils#update_winbar(a:kbuf)
endfunction

" The 'diagnostics' of the line {lnum}: [{message, severity}].
function! kube#table#diagnostics(kbuf, lnum) abort
  let placed = sign_getplaced(a:kbuf.bufnr, {'group': 'kube_diagnostics', 'lnum': a:lnum})[0].signs
  return map(filter(placed, 'has_key(a:kbuf.diagnostics, v:val.id)'), 'a:kbuf.diagnostics[v:val.id]')
endfunction

" The lines with diagnostics, in order.
function! kube#table#diagnostic_lines(kbuf) abort
  let placed = sign_getplaced(a:kbuf.bufnr, {'group': 'kube_diagnostics'})[0].signs
  return uniq(sort(map(placed, 'v:val.lnum'), 'n'))
endfunction

" Text cut to {width} display cells, ending with ...
function! s:truncate(text, width) abort
  if a:text !~# '[^\x00-\x7f]'
    return strpart(a:text, 0, a:width - 3) . '...'
  endif
  let result = ''
  let used = 0
  for char in split(a:text, '\zs')
    let used += strwidth(char)
    if used > a:width - 3
      break
    endif
    let result .= char
  endfor
  return result . '...'
endfunction

" Format {rows} under {headers}: returns [header_row, formatted_rows, widths].
" A formatted row: formatted (the line), cells, ranges (the 0-indexed byte
" range [start, end) of each cell), highlights, diagnostics, raw (the item).
function! kube#table#format_table(headers, rows) abort
  let widths = []
  for i in range(len(a:headers))
    let width = strwidth(a:headers[i])
    for row in a:rows
      let width = max([width, strwidth(get(row.row, i, ''))])
    endfor
    call add(widths, width)
  endfor

  let formatted_rows = []
  for row in a:rows
    let [formatted, ranges] = kube#table#align_row(row.row, widths)
    call add(formatted_rows, {
          \ 'formatted': formatted,
          \ 'ranges': ranges,
          \ 'cells': row.row,
          \ 'highlights': get(row, 'highlights', {}),
          \ 'diagnostics': get(row, 'diagnostics', []),
          \ 'raw': get(row, 'item', v:null),
          \ })
  endfor
  let header = {'formatted': kube#table#align_row(a:headers, widths)[0], 'highlight': 'KubeHeader', 'raw': a:headers}
  return [header, formatted_rows, widths]
endfunction

" Align the cells of {row} to {widths}: returns [line, ranges].
function! kube#table#align_row(row, widths) abort
  let cells = []
  let ranges = []
  let pos = 0
  for i in range(len(a:widths))
    let width = min([s:MAX_COLUMN_WIDTH, a:widths[i]])
    let cell = get(a:row, i, '')
    let cell_width = strwidth(cell)
    if cell_width > width
      let cell = s:truncate(cell, width)
      let cell_width = strwidth(cell)
    endif
    let cell .= repeat(' ', width - cell_width)
    call add(cells, cell)
    call add(ranges, [pos, pos + len(cell)])
    let pos += len(cell) + len(s:COLUMN_SEPARATOR)
  endfor
  return [join(cells, s:COLUMN_SEPARATOR), ranges]
endfunction
