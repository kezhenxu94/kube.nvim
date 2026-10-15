-- Minimal test runner: nvim --headless --clean -l tests/runner.lua tests/<name>_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = string.format("%s/tests/?.lua;%s", root, package.path)
-- The end-to-end tests use the real kubectl against a kind cluster
if not vim.env.KUBE_E2E_CONTEXT then
  vim.env.PATH = root .. "/tests/bin:" .. vim.env.PATH
end
vim.env.KUBE_TEST_DIR = vim.fn.tempname()
vim.fn.mkdir(vim.env.KUBE_TEST_DIR, "p")

local tests = {}
local suites = { { names = {}, before = {}, after = {} } }

function _G.describe(name, fn)
  local parent = suites[#suites]
  table.insert(suites, {
    names = vim.list_extend(vim.deepcopy(parent.names), { name }),
    before = vim.list_extend({}, parent.before),
    after = vim.list_extend({}, parent.after),
  })
  fn()
  table.remove(suites)
end

function _G.before_each(fn)
  table.insert(suites[#suites].before, fn)
end

function _G.after_each(fn)
  table.insert(suites[#suites].after, 1, fn)
end

function _G.it(name, fn)
  local suite = suites[#suites]
  table.insert(tests, {
    name = table.concat(vim.list_extend(vim.deepcopy(suite.names), { name }), " > "),
    before = vim.list_extend({}, suite.before),
    after = vim.list_extend({}, suite.after),
    fn = fn,
  })
end

local spec = assert(arg[1], "usage: runner.lua <spec file>")
dofile(spec)

local failed = 0
for _, test in ipairs(tests) do
  local ok, err = xpcall(function()
    for _, fn in ipairs(test.before) do
      fn()
    end
    test.fn()
  end, debug.traceback)
  for _, fn in ipairs(test.after) do
    local after_ok, after_err = xpcall(fn, debug.traceback)
    if ok and not after_ok then
      ok, err = false, after_err
    end
  end

  if ok then
    io.stdout:write("  ok   ", test.name, "\n")
  else
    failed = failed + 1
    io.stdout:write("  FAIL ", test.name, "\n", (tostring(err):gsub("\n", "\n       ")), "\n")
  end
end

io.stdout:write(string.format("%s: %d passed, %d failed\n\n", spec, #tests - failed, failed))
vim.fn.delete(vim.env.KUBE_TEST_DIR, "rf")
vim.cmd(failed > 0 and "cquit 1" or "qall!")
