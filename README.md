# kube.nvim

Neovim Kubernetes plugin, manage your Kubernetes resources like a buffer!

https://github.com/user-attachments/assets/822aa52d-f9ca-4208-bbfe-d2d95cfb90c5

## Installation

To install kube.nvim, use the LazyVim plugin manager. Add the following to your configuration file:

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

- `:Kube get pods`: Get all pods in all namespaces.
- `:Kube get deployments namespace=staging`: Get all deployments in the `staging` namespace.
- `:Kube get pods selector=app=nginx,revision=v1`: Get all pods with the `app=nginx` and `revision=v1` label.
- `:Kube delete pod test-pod`: Delete the pod named `test-pod`.
- `:Kube context`: Show available contexts and select to switch.
- `:Kube context production`: Switch to the `production` context.

See more details in [help file](./doc/kube-nvim.txt).

## Features

- **Resource Management**: Manage resources like a buffer, delete a line and save to delete the resource.
- **Log Viewing**: View logs for your Kubernetes resources, and follow/tail the logs right inside Neovim buffer.
- **Port Forwarding**: Forward ports for your Kubernetes resources.
- **Diagnostics**: Publish diagnostics for unhealthy/unready/failed resources, navigate to problematic resources with `]d`.
- **exec in to Pod container**: `exec` into Pod container right in Neovim. Select a Pod and press enter, then select a container and press enter!

## Keymaps

The following key mappings are available in kube.nvim:

`<cr>`: Drill down into the resource under the cursor.
`gd`: Describe the resource under the cursor.
`gl`: Show logs for the resource under the cursor.
`gL`: Follow logs for the resource under the cursor.
`gF`: Show port forwards for the resource under the cursor.
`gf`: Forward ports for the resource under the cursor.
`gy`: Show YAML for the resource under the cursor.
`ge`: Edit the resource under the cursor.
`gE`: Exec into the resource under the cursor.
`gi`: Set image for the resource under the cursor.
`gr`: Refresh the resources in the buffer.
`q`: Quit the buffer and wipe it out, if you only want to delete the buffer, use `:bd` or keymap like `<leader>bd`.

## Configurations

The following configuration options are available in kube.nvim:

- `keymaps`: A table of key mappings. The default values are:
  - `drill_down`: `<cr>`
  - `describe`: `gd`
  - `refresh`: `gr`
  - `show_logs`: `gl`
  - `follow_logs`: `gL`
  - `port_forward`: `gF`
  - `forward_port`: `gf`
  - `show_yaml`: `gy`
  - `edit`: `ge`
  - `set_image`: `gi`
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

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
