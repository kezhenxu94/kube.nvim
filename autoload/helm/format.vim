" Helm releases and revisions as table rows, they are not Kubernetes objects:
" they have no metadata.

let s:HIGHLIGHTS = {
      \ 'deployed': 'KubeRunning',
      \ 'superseded': 'KubeSucceeded',
      \ 'uninstalled': 'KubeSucceeded',
      \ 'failed': 'KubeFailed',
      \ 'unknown': 'KubeUnknown',
      \ }

" The highlight group of a release status.
function! helm#format#highlight(status) abort
  " pending-install, pending-upgrade, uninstalling, ...
  return get(s:HIGHLIGHTS, a:status, 'KubePending')
endfunction

" The time since {updated}, as helm outputs it: 2026-01-01 08:00:00.1 +0800 CST
" or 2026-01-01T08:00:00.1+08:00.
function! helm#format#age(updated) abort
  if type(a:updated) != v:t_string || a:updated !~# '^\d\{4}-\d\d-\d\d.\d\d:\d\d:\d\d'
    return ''
  endif
  let zone = matchlist(strpart(a:updated, 19), '\([+-]\)\(\d\d\):\=\(\d\d\)')
  let [sign, hours, minutes] = empty(zone) ? ['', 0, 0] : zone[1:3]
  let offset = empty(sign) ? 0 : (str2nr(hours) * 3600 + str2nr(minutes) * 60) * (sign ==# '-' ? -1 : 1)
  return kube#utils#format_duration(localtime() - (kube#utils#parse_time(a:updated) - offset))
endfunction

function! s:by_namespace(a, b) abort
  let a = [a:a.namespace, a:a.name]
  let b = [a:b.namespace, a:b.name]
  return a ==# b ? 0 : a[0] ># b[0] || (a[0] ==# b[0] && a[1] ># b[1]) ? 1 : -1
endfunction

" The releases of helm list.
function! helm#format#releases(releases, kbuf) abort
  let rows = []
  " By namespace like kubectl lists, helm sorts by name or date only
  for release in sort(copy(a:releases), function('s:by_namespace'))
    let status = kube#utils#get(release, 'status', 'unknown')
    let highlight = helm#format#highlight(status)
    let diagnostics = []
    if status ==# 'failed'
      call add(diagnostics, {'message': 'The release failed, see its history', 'severity': 'error'})
    elseif highlight !=# 'KubeRunning' && highlight !=# 'KubeSucceeded'
      call add(diagnostics, {'message': 'The release is ' . status, 'severity': 'warn'})
    endif
    call add(rows, {
          \ 'row': [release.namespace, release.name, resource#to_string(release.revision), status,
          \   kube#utils#get(release, 'chart', ''), kube#utils#get(release, 'app_version', ''),
          \   helm#format#age(get(release, 'updated', v:null))],
          \ 'highlights': {'STATUS': highlight},
          \ 'item': {
          \   'kind': 'HelmRelease',
          \   'name': release.name,
          \   'namespace': release.namespace,
          \   'revision': str2nr(resource#to_string(release.revision)),
          \   'status': status,
          \ },
          \ 'diagnostics': diagnostics,
          \ })
  endfor
  return rows
endfunction

" The revisions of helm history, the latest last as helm lists them.
function! helm#format#history(revisions, kbuf) abort
  let rows = []
  for revision in a:revisions
    let status = kube#utils#get(revision, 'status', '')
    call add(rows, {
          \ 'row': [resource#to_string(revision.revision), helm#format#age(get(revision, 'updated', v:null)), status,
          \   kube#utils#get(revision, 'chart', ''), kube#utils#get(revision, 'app_version', ''),
          \   kube#utils#get(revision, 'description', '')],
          \ 'highlights': {'STATUS': helm#format#highlight(empty(status) ? 'unknown' : status)},
          \ 'item': {
          \   'kind': 'HelmRevision',
          \   'name': resource#to_string(revision.revision),
          \   'release': a:kbuf.resource_name,
          \   'namespace': a:kbuf.namespace,
          \   'revision': str2nr(resource#to_string(revision.revision)),
          \ },
          \ })
  endfor
  return rows
endfunction
