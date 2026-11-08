# kube.nvim

Vim and Neovim Kubernetes plugin, manage your Kubernetes resources like a buffer!

[![kube.nvim demo](demo/kube-nvim.gif)](https://asciinema.org/a/ycGEDdCaHY7hDeDj)

For Docker, see [docker.nvim](https://github.com/kezhenxu94/docker.nvim), the same buffers for containers, images, volumes, networks and compose projects.

## Installation

Requirements: Vim >= 9.2 or Neovim >= 0.11, and `kubectl` in `$PATH`, `helm` too for Helm releases. No other plugin dependencies.

With Vim's packages:

```sh
git clone https://github.com/kezhenxu94/kube.nvim ~/.vim/pack/plugins/start/kube.nvim
```

With Neovim's built-in plugin manager, [`vim.pack`](https://neovim.io/doc/user/pack.html#vim.pack) (Neovim >= 0.12):

```lua
vim.pack.add({ "https://github.com/kezhenxu94/kube.nvim" })
```

Or with your plugin manager. Nothing to set up, `g:kube_*` variables change the [configuration](#configuration).

## Usage

* `:Kube get pods`: Pods in all namespaces.
* `:Kube get deployments namespace=staging`: Deployments in the `staging` namespace.
* `:Kube get pods selector=app=nginx,revision=v1`: Pods with the `app=nginx` and `revision=v1` labels.
* `:Kube delete pod test-pod`: Delete the pod named `test-pod`.
* `:Kube context`: Select the context to use, `:Kube context production` to switch to `production`. Only kube.nvim is affected, not your kubeconfig.
* `:Kube apply` / `:Kube diff`: Apply / diff the current buffer as a manifest, `:Kube! apply` applies without confirming.
* `:Kube portforwards`: All port forwards, delete a line and `:w` to stop one.
* `:Kube get helm`: Helm releases in all namespaces, `helm` is short for `helm-releases`.

Every view is a buffer named `kube://[context/{context}/][namespaces/{namespace}/]{kind}[/{name}[/{subresource}]][?{params}]`, so you can also open them directly:

* `:e kube://`: The resource types of the cluster, `<CR>` on one lists it.
* `:e kube://deployments`: Deployments in all namespaces, in the current context.
* `:e kube://namespaces/staging/deployments`: Deployments in the `staging` namespace, or `:e kube://ns/staging/deployments` for short.
* `:e kube://context/production/pods`: Pods in the `production` context, or `:e kube://ctx/production/pods` for short.
* `:e kube://ns/staging/helm`: Helm releases in the `staging` namespace.

A buffer opened without `context/{context}/` is bound to the context that was current when it was opened. Reloading, editing and deleting from it keep operating on that cluster even after you switch to another context.

Kube buffers behave like file buffers: every jump is an `:edit` in the current window, so `<C-o>`, `<C-^>`, `<C-t>`, `'hidden'` and `:bd` work as usual. See `:help kube-buffers`.

## Features

* **Edit the cluster like a buffer**: delete lines and `:w` to delete resources (deleted lines stay visible until written); edit DESIRED (deployments, statefulsets, replicasets), IMAGE (containers) or SUSPENDED (cron jobs) cells and `:w` to scale, set the image or suspend (`:w` refuses edits of other cells); edit the YAML and `:w` to apply it, after reviewing `kubectl diff` (`:w!` skips the confirmation).
* **Navigation**: `K` describes, `gd` / `<C-]>` jump to what the cell refers to, `gD` to the owner, `gra` offers every operation, on a visual selection for all selected resources.
* **Operations** (`gra`): scale, rollout restart / undo / history, cordon / uncordon / drain, set image, trigger a cron job now, delete, with confirmations naming the context.
* **Logs**: show / follow logs, of all containers, of the previous instance, since a duration; limited to the last 1000 lines by default. Following keeps the cursor at the end, like `tail -f`. Logs can be edited, e.g. `:%!jq`, `:%!jq .message -r` or `:%s/\\t/\t/g` to make them readable, `:w {file}` saves them.
* **Events**: per namespace or for the resource under the cursor, warnings marked as unhealthy.
* **Secrets**: view and edit decoded secret data.
* **Helm**: list releases of all statuses, failed ones marked as unhealthy; `<CR>` shows the manifest, `gd` the values, `K` the status; `gra` shows all values, notes and the history, rolls back to the previous revision or to one of the history, and uninstalls. Delete lines and `:w` to uninstall releases. Values are read-only, as a release does not record where its chart comes from.
* **Port forwarding**: forward ports of pods, deployments and services, `gx` opens them.
* **exec**: open a shell in a container right in the editor, in a terminal. Or in an ephemeral debug container (`kubectl debug`), for images without a shell.
* **Watch**: `gw` reloads a list periodically, keeping the cursor on the same resource.
* **Statuses like kubectl**: `CrashLoopBackOff`, `ImagePullBackOff`, `Init:0/1`, `NotReady,SchedulingDisabled`, ...
* **Metrics**: CPU and MEMORY columns for pods and nodes, when the cluster has the metrics API (metrics-server).
* **Unhealthy resources** are marked in the sign column, `]d` jumps to the next one, `<C-w>d` shows why.

## Keymaps

Keymaps follow the editor's conventions: `gd` / `K` / `<C-]>`, and the built-in directory browser's `<CR>` / `-` / `R`.

* `<CR>`: Drill down into the resource under the cursor (a pod's containers, a deployment's pods, a secret's data, ...).
* `gd`: Go to what the cell under the cursor refers to, the YAML of the resource for most cells.
* `gD`: Go to the owner of the resource: pod → replica set → deployment, job → cron job.
* `K`: Describe the resource under the cursor in a floating window, explain the resource type in `kube://`.
* `-`: Go to the parent buffer: resource → list in its namespace → list in all namespaces → namespaces → resource types.
* `R`: Reload the buffer, the cursor stays on the same resource.
* `gw`: Toggle reloading the list every `g:kube_refresh_interval`.
* `gl` / `gL`: Show / follow logs, `<C-c>` stops following.
* `gf` / `gF`: Forward ports / show the port forwards of the resource under the cursor.
* `gi`: Set image for the resource under the cursor.
* `gs`: Open a shell (`kubectl exec`) in the resource under the cursor.
* `gra`: All operations on the resource under the cursor, or on the resources of a visual selection.
* `]d` / `[d`: Next / previous unhealthy resource, `<C-w>d` shows why.
* `g?`: Show the help.

Built-in keys that work in kube buffers:

* `<C-]>`: Jump to what the cell under the cursor refers to: a NAMESPACE filters the list to that namespace, a NODE opens the node, an event's OBJECT the object, a namespace row lists its pods, a resource type lists it, anything else goes to the resource's YAML. `<C-t>` jumps back and `<C-w>]` opens the jump in a split, as with tags.
* `gx`: Open the port forward URL under the cursor.

See `:help kube.nvim` for the details.

## Configuration

Set these variables before kube buffers are opened, the defaults:

```vim
" Keymaps by action, '' disables one
let g:kube_keymaps = {
      \ 'drill_down': '<CR>', 'show_yaml': 'gd', 'owner': 'gD', 'describe': 'K',
      \ 'parent': '-', 'refresh': 'R', 'watch': 'gw', 'show_logs': 'gl',
      \ 'follow_logs': 'gL', 'port_forward': 'gF', 'forward_port': 'gf',
      \ 'set_image': 'gi', 'exec': 'gs', 'operations': 'gra', 'help': 'g?',
      \ }
" How often watched lists (gw) reload, in milliseconds, 0 to disable watching
let g:kube_refresh_interval = 10000
" kubectl --request-timeout, for everything except streams (logs -f, port-forward, exec, drain)
let g:kube_request_timeout = '30s'
" Log lines to fetch, -1 for all
let g:kube_logs_tail = 1000
" Log lines kept while following, -1 for all
let g:kube_logs_max_lines = 10000
" Highlight overrides, kept across colorschemes, as :highlight arguments, by default linked to your colorscheme's groups:
" KubeBody (Normal), KubePending (DiagnosticWarn in Neovim, WarningMsg in Vim), KubeRunning (Normal),
" KubeFailed (DiagnosticError, ErrorMsg), KubeSucceeded/KubeUnknown (Comment), KubeHeader (Title),
" KubeDeleted (DiffDelete): deleted lines, KubeChanged (DiffChange): lines a watched reload changed,
" KubeEditable (Identifier): cells of editable columns, KubeSign{Error,Warn,Info}: signs of unhealthy resources
let g:kube_highlights = {}
" e.g. let g:kube_highlights = {'KubeHeader': 'guifg=#df8e1d gui=bold'}
```

`g:kube_keymaps` only needs the keymaps to change, e.g. `let g:kube_keymaps = {'describe': 'gK'}`.

## Contributing

We welcome contributions to kube.nvim! If you would like to contribute, please follow these guidelines:

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that the code passes all tests.
3. Submit a pull request with a description of your changes.

* `make test`: Tests in Vim and in headless Neovim (`make test-vim` / `make test-nvim` for one of them, `VIM=` / `NVIM=` to pick the executables) against a fake `kubectl` (`tests/bin/kubectl`), never a real cluster.
* `make test-e2e`: End-to-end tests against a [kind](https://kind.sigs.k8s.io) cluster `kube-nvim-e2e`, created with its own kubeconfig (`.e2e-kubeconfig`) so your kubeconfig and current context are left untouched. `make e2e-clean` deletes it. Without a reachable cluster the end-to-end tests are skipped.

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
