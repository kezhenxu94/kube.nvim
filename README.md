# kube.nvim

Neovim Kubernetes plugin, manage your Kubernetes resources like a buffer!

https://github.com/user-attachments/assets/822aa52d-f9ca-4208-bbfe-d2d95cfb90c5

## Installation

Requirements: Neovim >= 0.11 and `kubectl` in `$PATH`. No other plugin dependencies.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "kezhenxu94/kube.nvim",
  config = function()
    require("kube").setup({})
  end,
}
```

## Usage

To use kube.nvim, you can run the following commands in Neovim:

* `:Kube get pods`: Get all pods in all namespaces.
* `:Kube get deployments namespace=staging`: Get all deployments in the `staging` namespace.
* `:Kube get pods selector=app=nginx,revision=v1`: Get all pods with the `app=nginx` and `revision=v1` label.
* `:Kube delete pod test-pod`: Delete the pod named `test-pod`.
* `:Kube context`: Show available contexts and select to switch.
* `:Kube context production`: Switch to the `production` context.

`:Kube context` only affects kube.nvim, not your kubeconfig.

### Buffer names

Every view is a buffer named `kube://[context/{context}/][namespaces/{namespace}/]{kind}[/{name}[/{subresource}]][?{params}]`, so you can also open them directly:

* `:e kube://deployments`: Deployments in all namespaces, in the current context.
* `:e kube://namespaces/staging/deployments`: Deployments in the `staging` namespace.
* `:e kube://context/production/pods`: Pods in the `production` context.

A buffer opened without `context/{context}/` is bound to the context that was current when it was opened (its name is rewritten to include it). Refreshing, editing and deleting from it keep operating on that cluster even after you switch to another context.

## Features

* **Resource Management**: Manage resources like a buffer, delete a line and save to delete the resource.
* **Log Viewing**: View logs for your Kubernetes resources, and follow/tail the logs right inside Neovim buffer.
* **Port Forwarding**: Forward ports for your Kubernetes resources.
* **Diagnostics**: Publish diagnostics for unhealthy/unready/failed resources, navigate to problematic resources with `]d`.
* **exec in to Pod container**: `exec` into Pod container right in Neovim. Select a Pod and press enter, then select a container and press enter!

## Keymaps

Keymaps follow Neovim's conventions: LSP's `gd` / `K` / `<C-]>`, and the built-in directory browser's `<CR>` / `-` / `R`.

* `<CR>`: Drill down into the resource under the cursor (a pod's containers, a deployment's pods, ...).
* `gd`: Go to the YAML definition of the resource under the cursor. Edit it and `:w` to apply.
* `K`: Describe the resource under the cursor.
* `-`: Go to the parent buffer: resource → list in its namespace → list in all namespaces → namespaces.
* `R`: Reload the buffer, the cursor stays on the same resource.
* `gl` / `gL`: Show / follow logs for the resource under the cursor, `<C-c>` stops following.
* `gf`: Forward ports for the resource under the cursor.
* `gF`: Show port forwards for the resource under the cursor.
* `gi`: Set image for the resource under the cursor.
* `gs`: Open a shell (`kubectl exec`) in the resource under the cursor.
* `g?`: Show the help.
* `q`: Quit the buffer and wipe it out, if you only want to delete the buffer, use `:bd` or keymap like `<leader>bd`.

Built-in keys that work in kube buffers:

* `<C-]>`: Jump to what the cell under the cursor refers to: a NAMESPACE filters the list to that namespace, a NODE opens the node, a namespace row lists its pods, anything else goes to the resource's YAML definition. `<C-t>` jumps back and `<C-w>]` opens the jump in a split, as with tags.
* `]d` / `[d`: Next / previous unhealthy resource, `<C-w>d` shows why.
* `gx`: Open the port forward URL under the cursor.

## Configurations

The following configuration options are available in kube.nvim:

- `keymaps`: A table of key mappings. The default values are:
  - `drill_down`: `<cr>`
  - `show_yaml`: `gd`
  - `describe`: `K`
  - `parent`: `-`
  - `refresh`: `R`
  - `show_logs`: `gl`
  - `follow_logs`: `gL`
  - `port_forward`: `gF`
  - `forward_port`: `gf`
  - `set_image`: `gi`
  - `exec`: `gs`
  - `quit`: `q`
  - `help`: `g?`
- `highlights`: A table of highlight groups. The default values are:
  - `KubeBody`: `{ fg = "#40a02b" }`
  - `KubePending`: `{ fg = "#fe640b" }`
  - `KubeRunning`: `{ fg = "#40a02b" }`
  - `KubeFailed`: `{ fg = "#d20f39" }`
  - `KubeSucceeded`: `{ fg = "#9ca0b0" }`
  - `KubeUnknown`: `{ fg = "#6c6f85" }`
  - `KubeHeader`: `{ fg = "#df8e1d", bold = true }`

## Contributing

We welcome contributions to kube.nvim! If you would like to contribute, please follow these guidelines:

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that the code passes all tests.
3. Submit a pull request with a description of your changes.

Run the tests with `make test`. They run in headless Neovim against a fake `kubectl` (`tests/bin/kubectl`), never a real cluster.

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
