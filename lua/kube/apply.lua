local kubectl = require("kubectl")

local M = {}

---Show `text` in a scratch split with `filetype`, returning its window.
---@param lines string[]
---@param filetype string
---@return integer win
function M.show_split(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, false, {
    split = "below",
    win = -1,
    height = math.max(3, math.min(#lines, math.floor(vim.o.lines / 2))),
  })
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  return win
end

---@param title string
---@param on_choice fun(confirmed: boolean)
function M.confirm(title, on_choice)
  vim.ui.select({ "Yes", "No" }, { prompt = title }, function(choice)
    on_choice(choice == "Yes")
  end)
end

---Apply a manifest, after showing its diff against the cluster and confirming unless `force`.
---@param context string|nil
---@param namespace string|nil
---@param file string The manifest
---@param opts {force: boolean|nil, title: string}
---@param done fun(applied: boolean) `applied` is also true when there was nothing to apply
function M.apply(context, namespace, file, opts, done)
  local function apply()
    kubectl.apply(context, namespace, file, function(result)
      if result then
        vim.notify(vim.trim(result))
      end
      done(result ~= nil)
    end, function(err)
      vim.notify("Failed to apply: " .. err, vim.log.levels.ERROR)
    end)
  end

  if opts.force then
    apply()
    return
  end

  kubectl.diff(context, namespace, file, function(diff)
    if diff == nil then
      done(false)
      return
    end
    if diff == "" then
      vim.notify("No changes to apply")
      done(true)
      return
    end

    local win = M.show_split(vim.split(vim.trim(diff), "\n"), "diff")
    -- Show the diff before prompting: the default vim.ui.select blocks in the message area
    vim.cmd.redraw()
    M.confirm(opts.title, function(confirmed)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if confirmed then
        apply()
      else
        done(false)
      end
    end)
  end, function(err)
    vim.notify("Failed to diff: " .. err, vim.log.levels.ERROR)
  end)
end

---Write lines to a temporary manifest, removed once `fn` calls its callback.
---@param lines string[]
---@param fn fun(file: string, cleanup: fun())
function M.with_temp_file(lines, fn)
  local file = vim.fn.tempname() .. ".yaml"
  vim.fn.writefile(lines, file)
  fn(file, function()
    vim.fn.delete(file)
  end)
end

return M
