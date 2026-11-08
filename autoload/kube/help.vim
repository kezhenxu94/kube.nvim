" The help of kube buffers, g?.

function! kube#help#lines() abort
  let lines = ['Keymaps']
  for [lhs, description] in kube#keymaps#list()
    call add(lines, printf('  %-8s %s', lhs, description))
  endfor
  return lines + [
        \ '',
        \ 'Built-in keys that also work',
        \ "  <C-]>    jump to what the cell under the cursor refers to: NAMESPACE",
        \ '           filters the list, NODE opens the node, an event''s OBJECT the',
        \ '           object, a namespace row lists its pods, a resource type lists',
        \ '           it, else the YAML',
        \ '  <C-t>    jump back, <C-w>] opens the jump in a split',
        \ '  ]d [d    next / previous unhealthy resource, <C-w>d shows why',
        \ '  gx       open the port forward URL under the cursor',
        \ '',
        \ 'Editing, :w applies after confirming, :w! without confirming',
        \ '  lists    delete lines to delete the resources, uninstall the releases',
        \ '  YAML     (gd) shows `kubectl diff` before applying',
        \ '  secrets  (<CR> on a secret) decoded `key: "value"` lines',
        \ '',
        \ 'Commands',
        \ '  :Kube get {kind} [namespace={ns}] [selector={labels}]',
        \ '  :Kube delete {kind} {name} [namespace={ns}]',
        \ '  :Kube context [{context}]',
        \ '  :Kube[!] apply / :Kube diff   the current buffer as a manifest',
        \ '  :Kube portforwards            all port forwards',
        \ '',
        \ 'Buffer names',
        \ '  kube://[context/{context}/][namespaces/{ns}/]{kind}[/{name}[/{subresource}]]',
        \ '  Without context/{context}/ the current context is used and the buffer',
        \ '  stays bound to it, e.g. :e kube://deployments',
        \ '  :e kube:// lists the resource types, :e kube://helm the Helm releases',
        \ '',
        \ 'More in :help kube.nvim',
        \ ]
endfunction

" Show the help in a floating window.
function! kube#help#show() abort
  return kube#compat#float(kube#help#lines(), {'enter': 1, 'title': ' kube.nvim ', 'close_keys': [kube#config#get('keymaps').help]})
endfunction
