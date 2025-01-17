# kube.nvim

kube.nvim is a Neovim plugin that provides an interface for managing Kubernetes resources directly from your editor. It allows you to view logs, forward ports, and manage resources without leaving Neovim.

## Installation

To install kube.nvim, use the LazyVim plugin manager. Add the following to your `lazy.lua` configuration file:

```lua
{
  "kezhenxu94/kube.nvim",
  config = function()
    require("kube").setup()
  end,
}
```

Then, run `:Lazy sync` to install the plugin.

## Usage

To use kube.nvim, you can run the following commands in Neovim:

- `:KubeGet <resource>`: Get a list of resources of the specified type.
- `:KubeDelete <resource> <name>`: Delete the specified resource.
- `:KubeContext <context>`: Switch to the specified Kubernetes context.

## Features

- **Resource Management**: Easily manage Kubernetes resources directly from Neovim.
- **Log Viewing**: View logs for your Kubernetes resources.
- **Port Forwarding**: Forward ports for your Kubernetes resources.

## Contributing

We welcome contributions to kube.nvim! If you would like to contribute, please follow these guidelines:

1. Fork the repository and create a new branch for your changes.
2. Make your changes and ensure that the code passes all tests.
3. Submit a pull request with a description of your changes.

If you encounter any issues or have any questions, please open an issue on the repository.

## License

kube.nvim is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
