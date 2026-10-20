local M = {}

---@param buf_nr number The kube buffer to show the help for
---@return string[]
function M.lines(buf_nr)
  local keymaps = vim.tbl_filter(function(keymap)
    return keymap.desc and vim.startswith(keymap.desc, "kube: ")
  end, vim.api.nvim_buf_get_keymap(buf_nr, "n"))
  table.sort(keymaps, function(a, b)
    return a.lhs < b.lhs
  end)

  local lines = { "Keymaps" }
  for _, keymap in ipairs(keymaps) do
    table.insert(lines, string.format("  %-8s %s", keymap.lhs, keymap.desc:sub(#"kube: " + 1)))
  end

  vim.list_extend(lines, {
    "",
    "Built-in keys that also work",
    "  <C-]>    jump to what the cell under the cursor refers to: NAMESPACE",
    "           filters the list, NODE opens the node, an event's OBJECT the",
    "           object, a namespace row lists its pods, a resource type lists",
    "           it, else the YAML",
    "  <C-t>    jump back, <C-w>] opens the jump in a split",
    "  gra      all operations on the resource, or on a visual selection:",
    "           scale, restart, undo, history, events, logs, debug, trigger,",
    "           cordon, drain, ...",
    "  gO       the resources as an outline (LSP document symbols)",
    "  ]d [d    next / previous unhealthy resource, <C-w>d shows why",
    "  gx       open the port forward URL under the cursor",
    "",
    "Editing, :w applies after confirming, :w! without confirming",
    "  lists    delete lines to delete the resources",
    "  YAML     (gd) shows `kubectl diff` before applying",
    '  secrets  (<CR> on a secret) decoded `key: "value"` lines',
    "",
    "Commands",
    "  :Kube get {kind} [namespace={ns}] [selector={labels}]",
    "  :Kube delete {kind} {name} [namespace={ns}]",
    "  :Kube context [{context}]",
    "  :Kube[!] apply / :Kube diff   the current buffer as a manifest",
    "  :Kube portforwards            all port forwards",
    "",
    "Buffer names",
    "  kube://[context/{context}/][namespaces/{ns}/]{kind}[/{name}[/{subresource}]]",
    "  Without context/{context}/ the current context is used and the buffer",
    "  stays bound to it, e.g. :e kube://deployments",
    "  :e kube:// lists the resource types",
    "",
    "More in :help kube.nvim",
  })
  return lines
end

---Show the help in a floating window.
---@param buf_nr number The kube buffer to show the help for
function M.show(buf_nr)
  local lines = M.lines(buf_nr)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(help_buf, true, {
    relative = "editor",
    width = math.min(width + 2, vim.o.columns - 4),
    height = math.min(#lines, vim.o.lines - 4),
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " kube.nvim ",
    title_pos = "center",
  })

  for _, lhs in ipairs({ "q", "<Esc>", "g?" }) do
    vim.keymap.set("n", lhs, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = help_buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = help_buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
