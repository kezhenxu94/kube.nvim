" Secret data as editable text: one `key: "value"` per line in JSON string
" syntax (also valid YAML), `key: !!binary "base64"` for values that are not
" UTF-8.

let s:BINARY_TAG = '!!binary '

let s:HEADER = [
      \ '# Decoded secret data, one `key: "value"` per line (JSON string syntax).',
      \ '# Values that are not UTF-8 are shown as `key: !!binary "<base64>"`.',
      \ '# :w updates the secret, keys removed here are deleted from it.',
      \ ]

let s:ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

" The bytes of {text}.
function! s:bytes(text) abort
  return map(range(len(a:text)), 'char2nr(a:text[v:val])')
endfunction

" The text of {bytes}.
function! s:text(bytes) abort
  return eval('"' . join(map(copy(a:bytes), 'printf("\\x%02x", v:val)'), '') . '"')
endfunction

function! kube#secret#base64_encode(bytes) abort
  let result = ''
  for i in range(0, len(a:bytes) - 1, 3)
    let chunk = a:bytes[i : i + 2]
    let n = chunk[0] * 65536 + get(chunk, 1, 0) * 256 + get(chunk, 2, 0)
    let encoded = s:ALPHABET[n / 262144] . s:ALPHABET[n / 4096 % 64] . s:ALPHABET[n / 64 % 64] . s:ALPHABET[n % 64]
    let result .= encoded[0 : len(chunk)] . repeat('=', 3 - len(chunk))
  endfor
  return result
endfunction

" The bytes of the base64 {text}, v:null when invalid.
function! kube#secret#base64_decode(text) abort
  if len(a:text) % 4 != 0 || a:text !~# '^[A-Za-z0-9+/]*=\{0,2}$'
    return v:null
  endif
  let bytes = []
  for i in range(0, len(a:text) - 1, 4)
    let chunk = substitute(a:text[i : i + 3], '=', '', 'g')
    let n = 0
    for char in split(chunk, '\zs')
      let n = n * 64 + stridx(s:ALPHABET, char)
    endfor
    let n = n * float2nr(pow(64, 4 - len(chunk)))
    call extend(bytes, [n / 65536, n / 256 % 256, n % 256][0 : len(chunk) - 2])
  endfor
  return bytes
endfunction

" Whether {bytes} are UTF-8, without NUL which text cannot hold.
function! s:is_utf8(bytes) abort
  let i = 0
  let n = len(a:bytes)
  while i < n
    let c = a:bytes[i]
    let length = c == 0 ? 0 : c < 0x80 ? 1 : (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3 : (c >= 0xF0 && c <= 0xF4) ? 4 : 0
    if length == 0 || i + length > n
      return 0
    endif
    for j in range(i + 1, i + length - 1)
      if a:bytes[j] < 0x80 || a:bytes[j] > 0xBF
        return 0
      endif
    endfor
    let i += length
  endwhile
  return 1
endfunction

" The lines of the secret's base64 encoded {data}.
function! kube#secret#to_lines(data) abort
  let lines = copy(s:HEADER)
  for key in sort(keys(a:data))
    let bytes = kube#secret#base64_decode(a:data[key])
    if bytes isnot v:null && s:is_utf8(bytes)
      call add(lines, printf('%s: %s', key, json_encode(s:text(bytes))))
    else
      call add(lines, printf('%s: %s%s', key, s:BINARY_TAG, json_encode(a:data[key])))
    endif
  endfor
  return lines
endfunction

" The base64 encoded data of {lines}: [data, error], data is v:null when
" invalid.
function! kube#secret#from_lines(lines) abort
  let data = {}
  let lnum = 0
  for line in a:lines
    let lnum += 1
    if line =~# '^\s*$' || line =~# '^\s*#'
      continue
    endif
    let [key, quoted] = (matchlist(line, '^\([[:alnum:]._-]\+\):\s*\(.\{-}\)\s*$') + ['', '', ''])[1:2]
    let binary = stridx(quoted, s:BINARY_TAG) == 0
    if binary
      let quoted = trim(strpart(quoted, len(s:BINARY_TAG)))
    endif
    try
      let value = json_decode(quoted)
    catch
      let value = v:null
    endtry
    if empty(key) || type(value) != v:t_string
      return [v:null, printf('line %d: expected `key: "value"`', lnum)]
    endif
    if has_key(data, key)
      return [v:null, printf('line %d: duplicate key %s', lnum, key)]
    endif
    if binary
      if kube#secret#base64_decode(value) is v:null
        return [v:null, printf('line %d: invalid base64', lnum)]
      endif
      let data[key] = value
    else
      let data[key] = kube#secret#base64_encode(s:bytes(value))
    endif
  endfor
  return [data, '']
endfunction

" A JSON merge patch turning {old} data into {new}: [patch, changes], patch
" is v:null when nothing changed, changes is {added, changed, removed}.
function! kube#secret#patch(old, new) abort
  let changes = {'added': [], 'changed': [], 'removed': []}
  let data = {}
  for [key, value] in items(a:new)
    if !has_key(a:old, key)
      call add(changes.added, key)
      let data[key] = value
    elseif a:old[key] !=# value
      call add(changes.changed, key)
      let data[key] = value
    endif
  endfor
  for key in keys(a:old)
    if !has_key(a:new, key)
      call add(changes.removed, key)
      let data[key] = v:null
    endif
  endfor
  call map(changes, 'sort(v:val)')
  return [empty(data) ? v:null : {'data': data}, changes]
endfunction
