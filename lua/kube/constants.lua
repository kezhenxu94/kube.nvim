local M = {}

M.KUBE_NAMESPACE = vim.api.nvim_create_namespace("kube")
M.KUBE_COLUMN_NAMESPACE = vim.api.nvim_create_namespace("kube_column")

M.KUBE_DIAGNOSTICS_NAMESPACE = vim.api.nvim_create_namespace("kube_diagnostics")

return M
