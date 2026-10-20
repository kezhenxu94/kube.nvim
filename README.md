# kube.nvim

Neovim Kubernetes plugin, manage your Kubernetes resources like a buffer!

[![kube.nvim demo](demo/kube-nvim.gif)](https://asciinema.org/a/ycGEDdCaHY7hDeDj)

## Installation

Requirements: Neovim >= 0.11 and `kubectl` in `$PATH`, `helm` too for Helm releases. No other plugin dependencies.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "kezhenxu94/kube.nvim" }
```

`setup()` is optional, call it only to change the [configuration](#configuration). Run `:checkhealth kube` to check kubectl and the cluster.

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
* `:e kube://context/production/pods`: Pods in the `production` context.
* `:e kube://ns/staging/helm`: Helm releases in the `staging` namespace.

A buffer opened without `context/{context}/` is bound to the context that was current when it was opened. Reloading, editing and deleting from it keep operating on that cluster even after you switch to another context.

Kube buffers behave like file buffers: every jump is an `:edit` in the current window, so `<C-o>`, `<C-^>`, `<C-t>`, `'hidden'` and `:bd` work as usual. See `:help kube-buffers`.

## Features

* **Edit the cluster like a buffer**: delete lines and `:w` to delete resources (deleted lines stay visible until written); edit DESIRED (deployments, statefulsets, replicasets), IMAGE (containers) or SUSPENDED (cron jobs) cells and `:w` to scale, set the image or suspend (`:w` refuses edits of other cells); edit the YAML and `:w` to apply it, after reviewing `kubectl diff` (`:w!` skips the confirmation).
* **LSP**: kube buffers have an in-process language server, so LSP keymaps and pickers work: `K` describes, `gd` / `<C-]>` jump to what the cell refers to, `gD` to the owner, `grr` lists the pods using a config map, secret, PVC, service account or node, `gO` lists the resources, `an` / `in` select the cell, then the row (e.g. `can` to edit a cell), `gra` offers every operation, on a visual selection for all selected resources, and code lenses on the containers of a YAML show / follow logs or exec (`grx`).
* **Operations**: scale, rollout restart / undo / history, cordon / uncordon / drain, set image, trigger a cron job now, delete, with confirmations naming the context.
* **Logs**: show / follow logs, of all containers, of the previous instance, since a duration; limited to the last 1000 lines by default. Following keeps the cursor at the end, like `tail -f`. Logs can be edited, e.g. `:%!jq`, `:%!jq .message -r` or `:%s/\\t/\t/g` to make them readable, `:w {file}` saves them.
* **Events**: per namespace or for the resource under the cursor, warnings as diagnostics.
* **Secrets**: view and edit decoded secret data.
* **Helm**: list releases of all statuses, failed ones as diagnostics; `<CR>` shows the manifest, `gd` the values, `K` the status; `gra` shows all values, notes and the history, rolls back to the previous revision or to one of the history, and uninstalls. Delete lines and `:w` to uninstall releases. Values are read-only, as a release does not record where its chart comes from.
* **Port forwarding**: forward ports of pods, deployments and services, `gx` opens them.
* **exec**: open a shell in a container right in Neovim. Or in an ephemeral debug container (`kubectl debug`), for images without a shell.
* **Watch**: `gw` reloads a list periodically, keeping the cursor on the same resource.
* **Statuses like kubectl**: `CrashLoopBackOff`, `ImagePullBackOff`, `Init:0/1`, `NotReady,SchedulingDisabled`, ...
* **Metrics**: CPU and MEMORY columns for pods and nodes, when the cluster has the metrics API (metrics-server).
* **Diagnostics**: unhealthy resources are diagnostics, `]d` jumps to the next one.

## Keymaps

Keymaps follow Neovim's conventions: LSP's `gd` / `K` / `<C-]>`, and the built-in directory browser's `<CR>` / `-` / `R`.

* `<CR>`: Drill down into the resource under the cursor (a pod's containers, a deployment's pods, a secret's data, ...).
* `gd`: Go to what the cell under the cursor refers to, the YAML of the resource for most cells.
* `K`: Describe the resource under the cursor, or explain the resource type in `kube://`.
* `-`: Go to the parent buffer: resource → list in its namespace → list in all namespaces → namespaces → resource types.
* `R`: Reload the buffer, the cursor stays on the same resource.
* `gw`: Toggle reloading the list every `refresh_interval`.
* `gl` / `gL`: Show / follow logs, `<C-c>` stops following.
* `gf` / `gF`: Forward ports / show the port forwards of the resource under the cursor.
* `gi`: Set image for the resource under the cursor.
* `gs`: Open a shell (`kubectl exec`) in the resource under the cursor.
* `g?`: Show the help.

Built-in keys that work in kube buffers:

* `<C-]>`: Jump to what the cell under the cursor refers to: a NAMESPACE filters the list to that namespace, a NODE opens the node, an event's OBJECT the object, a namespace row lists its pods, a resource type lists it, anything else goes to the resource's YAML. `<C-t>` jumps back and `<C-w>]` opens the jump in a split, as with tags.
* `gra`: All operations on the resource under the cursor, or on the resources of a visual selection.
* `]d` / `[d`: Next / previous unhealthy resource, `<C-w>d` shows why.
* `gx`: Open the port forward URL under the cursor.

See `:help kube.nvim` for the details.

## Configuration

The defaults:

```lua
require("kube").setup({
  keymaps = {
    drill_down = "<cr>",
    show_yaml = "gd",
    describe = "K",
    parent = "-",
    refresh = "R",
    watch = "gw",
    show_logs = "gl",
    follow_logs = "gL",
    port_forward = "gF",
    forward_port = "gf",
    set_image = "gi",
    exec = "gs",
    help = "g?",
  },
  -- How often watched lists (gw) reload, in milliseconds, false to disable watching
  refresh_interval = 10000,
  -- kubectl --request-timeout, for everything except streams (logs -f, port-forward, exec, drain)
  request_timeout = "30s",
  logs = {
    tail = 1000, -- Lines to fetch, -1 for all
    max_lines = 10000, -- Lines kept while following, -1 for all
  },
  -- Highlight overrides, by default linked to your colorscheme's groups:
  -- KubeBody (Normal), KubePending (DiagnosticWarn), KubeRunning (Normal),
  -- KubeFailed (DiagnosticError), KubeSucceeded/KubeUnknown (Comment), KubeHeader (Title),
  -- KubeDeleted (DiffDelete): deleted lines, KubeChanged (DiffChange): lines a watched reload changed,
  -- KubeEditable (Identifier): cells of editable columns
  -- e.g. { KubeHeader = { fg = "#df8e1d", bold = true } }
  highlights = {},
})
```

## Contributing

We welcome contributions to kube.nvim! If you would like to contribute, please follow these guidelines:

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that the code passes all tests.
3. Submit a pull request with a description of your changes.

* `make test`: Tests in headless Neovim against a fake `kubectl` (`tests/bin/kubectl`), never a real cluster.
* `make test-e2e`: End-to-end tests against a [kind](https://kind.sigs.k8s.io) cluster `kube-nvim-e2e`, created with its own kubeconfig (`.e2e-kubeconfig`) so your kubeconfig and current context are left untouched. `make e2e-clean` deletes it.
* `make lint`: Check the formatting with [StyLua](https://github.com/JohnnyMorganz/StyLua).

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
