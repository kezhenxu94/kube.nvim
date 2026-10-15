local M = {}

local dir = assert(vim.env.KUBE_TEST_DIR)
local fixtures = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/fixtures"

---@type {pattern: string, script: string}[]
local rules = {}

local function write_rules()
  local lines = {}
  for _, rule in ipairs(rules) do
    table.insert(lines, rule.pattern .. "\t" .. rule.script)
  end
  vim.fn.writefile(lines, dir .. "/rules")
end

---@param name string
---@return string
function M.fixture(name)
  return table.concat(vim.fn.readfile(fixtures .. "/" .. name), "\n")
end

---Make the fake kubectl reply to calls whose arguments match the shell glob `pattern`.
---Later rules take precedence.
---@param pattern string
---@param opts {stdout?: string, stderr?: string, code?: integer, fixture?: string, script?: string}
function M.respond(pattern, opts)
  local base = string.format("%s/rule%d", dir, #rules + 1)
  local script = opts.script
  if not script then
    vim.fn.writefile(
      vim.split(opts.fixture and M.fixture(opts.fixture) or opts.stdout or "", "\n"),
      base .. ".out",
      "b"
    )
    vim.fn.writefile(vim.split(opts.stderr or "", "\n"), base .. ".err", "b")
    script = string.format("cat '%s.out'; cat '%s.err' >&2; exit %d", base, base, opts.code or 0)
  end
  vim.fn.writefile({ script }, base .. ".sh")
  table.insert(rules, 1, { pattern = pattern, script = base .. ".sh" })
  write_rules()
end

---@return string[] The arguments of each kubectl call since the last reset
function M.calls()
  local file = dir .. "/calls"
  return vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or {}
end

---@param pattern string Lua pattern
---@return string[] The calls matching the pattern
function M.calls_matching(pattern)
  return vim.tbl_filter(function(call)
    return call:find(pattern) ~= nil
  end, M.calls())
end

function M.reset_kubectl()
  rules = {}
  write_rules()
  vim.fn.delete(dir .. "/calls")
end

---@param fn fun(): any
---@param what string|nil Description for the timeout error
function M.wait_for(fn, what)
  if not vim.wait(5000, function()
    return fn() and true or false
  end, 10) then
    error("timed out waiting for " .. (what or "condition"), 2)
  end
end

function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format(
        "%sexpected: %s\n  actual: %s",
        msg and (msg .. "\n") or "",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

function M.ok(value, msg)
  if not value then
    error(msg or "expected a truthy value", 2)
  end
end

---Replace `tbl[key]` until `restore_stubs` is called.
local stubs = {}
function M.stub(tbl, key, value)
  table.insert(stubs, { tbl, key, tbl[key] })
  tbl[key] = value
end

function M.restore_stubs()
  for i = #stubs, 1, -1 do
    local tbl, key, value = unpack(stubs[i])
    tbl[key] = value
  end
  stubs = {}
end

---Answer vim.ui.select / vim.ui.input prompts.
---@param select_answer (fun(items: any[], opts: table): any)|nil Returns the chosen item
---@param input_answer string|nil
function M.answer_prompts(select_answer, input_answer)
  M.stub(vim.ui, "select", function(items, opts, on_choice)
    local choice = select_answer and select_answer(items, opts)
    on_choice(choice, choice and vim.fn.index(items, choice) + 1 or nil)
  end)
  M.stub(vim.ui, "input", function(_, on_confirm)
    on_confirm(input_answer)
  end)
end

---Capture vim.notify messages.
---@return {msg: string, level: integer|nil}[]
function M.capture_notify()
  local messages = {}
  M.stub(vim, "notify", function(msg, level)
    table.insert(messages, { msg = msg, level = level })
  end)
  return messages
end

---Kill kube jobs and wipe every buffer, leaving an empty one.
function M.clean_buffers()
  vim.cmd("silent! %bwipeout!")
  M.wait_for(function()
    return vim.tbl_isempty(_G.kube_buffers or {})
  end, "kube buffers to be cleaned up")
end

---@param buf integer|nil
---@return string[]
function M.lines(buf)
  return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

---Wait for the current kube buffer to finish loading.
function M.wait_loaded()
  local buf = vim.api.nvim_get_current_buf()
  M.wait_for(function()
    local kbuf = _G.kube_buffers[buf]
    return kbuf and kbuf.loading_job and kbuf.loading_job:is_closing()
  end, "buffer to load")
  -- Let the scheduled render callback run
  vim.wait(20)
end

---Move the cursor to the first occurrence of `text` and press `keys`.
---@param text string
---@param keys string
function M.press_on(text, keys)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local lnum = vim.fn.search("\\V" .. text:gsub("\\", "\\\\"), "cW")
  assert(lnum > 0, "line not found: " .. text)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

return M
