# kube.nvim

Neovim Kubernetes plugin, manage your Kubernetes resources like a buffer!

https://github.com/user-attachments/assets/822aa52d-f9ca-4208-bbfe-d2d95cfb90c5

## Installation

Requirements: Neovim >= 0.11 and `kubectl` in `$PATH`. No other plugin dependencies.

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

Every view is a buffer named `kube://[context/{context}/][namespaces/{namespace}/]{kind}[/{name}[/{subresource}]][?{params}]`, so you can also open them directly:

* `:e kube://deployments`: Deployments in all namespaces, in the current context.
* `:e kube://namespaces/staging/deployments`: Deployments in the `staging` namespace.
* `:e kube://context/production/pods`: Pods in the `production` context.

A buffer opened without `context/{context}/` is bound to the context that was current when it was opened. Reloading, editing and deleting from it keep operating on that cluster even after you switch to another context.

## Features

* **Edit the cluster like a buffer**: delete lines and `:w` to delete resources; edit the YAML and `:w` to apply it, after reviewing `kubectl diff` (`:w!` skips the confirmation).
* **LSP**: kube buffers have an in-process language server, so LSP keymaps and pickers work: `K` describes, `gd` / `<C-]>` jump to what the cell refers to, `gO` lists the resources, and `gra` offers every operation, on a visual selection for all selected resources.
* **Operations**: scale, rollout restart / undo / history, cordon / uncordon / drain, set image, delete, with confirmations naming the context.
* **Logs**: show / follow logs, of all containers, of the previous instance, since a duration; limited to the last 1000 lines by default.
* **Events**: per namespace or for the resource under the cursor, warnings as diagnostics.
* **Secrets**: view and edit decoded secret data.
* **Port forwarding**: forward ports of pods, deployments and services, `gx` opens them.
* **exec**: open a shell in a container right in Neovim.
* **Watch**: `gw` reloads a list periodically, keeping the cursor on the same resource.
* **Diagnostics**: unhealthy resources are diagnostics, `]d` jumps to the next one.

## Keymaps

Keymaps follow Neovim's conventions: LSP's `gd` / `K` / `<C-]>`, and the built-in directory browser's `<CR>` / `-` / `R`.

* `<CR>`: Drill down into the resource under the cursor (a pod's containers, a deployment's pods, a secret's data, ...).
* `gd`: Go to what the cell under the cursor refers to, the YAML of the resource for most cells.
* `K`: Describe the resource under the cursor.
* `-`: Go to the parent buffer: resource → list in its namespace → list in all namespaces → namespaces.
* `R`: Reload the buffer, the cursor stays on the same resource.
* `gw`: Toggle reloading the list every `refresh_interval`.
* `gl` / `gL`: Show / follow logs, `<C-c>` stops following.
* `gf` / `gF`: Forward ports / show the port forwards of the resource under the cursor.
* `gi`: Set image for the resource under the cursor.
* `gs`: Open a shell (`kubectl exec`) in the resource under the cursor.
* `g?`: Show the help.
* `q`: Quit the buffer and wipe it out, if you only want to delete the buffer, use `:bd` or keymap like `<leader>bd`.

Built-in keys that work in kube buffers:

* `<C-]>`: Jump to what the cell under the cursor refers to: a NAMESPACE filters the list to that namespace, a NODE opens the node, an event's OBJECT the object, a namespace row lists its pods, anything else goes to the resource's YAML. `<C-t>` jumps back and `<C-w>]` opens the jump in a split, as with tags.
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
    quit = "q",
    help = "g?",
  },
  -- How often watched lists (gw) reload, in milliseconds, false to disable watching
  refresh_interval = 10000,
  -- kubectl --request-timeout, for everything except streams (logs -f, port-forward, exec, drain)
  request_timeout = "30s",
  logs = { tail = 1000 }, -- -1 for all
  -- Highlight overrides, by default linked to your colorscheme's groups:
  -- KubeBody (Normal), KubePending (DiagnosticWarn), KubeRunning (Normal),
  -- KubeFailed (DiagnosticError), KubeSucceeded/KubeUnknown (Comment), KubeHeader (Title)
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
