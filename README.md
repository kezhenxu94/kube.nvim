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
- `:Kube delete pod test-pod`: Delete the pod named `test-pod`.
- `:Kube context`: Show available contexts and select to switch.
- `:Kube context production`: Switch to the `production` context.

See more details in [help file](./doc/kube-nvim.txt).

## Features

- **Resource Management**: Manage resources like a buffer, delete a line and save to delete the resource.
- **Log Viewing**: View logs for your Kubernetes resources, and follow/tail the logs right inside Neovim buffer.
- **Port Forwarding**: Forward ports for your Kubernetes resources.
- **Diagnostics**: Publish diagnostics for unhealthy/unready/failed resources, navigate to problematic resources with `]d`.

## Contributing

We welcome contributions to kube.nvim! If you would like to contribute, please follow these guidelines:

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that the code passes all tests.
3. Submit a pull request with a description of your changes.

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
