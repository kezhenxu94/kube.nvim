-- End-to-end tests against a kind cluster, see `make test-e2e`
local t = require("helpers")

local CONTEXT = assert(vim.env.KUBE_E2E_CONTEXT, "KUBE_E2E_CONTEXT is required")
local NS = "kube-e2e"
local TIMEOUT = 60000

require("kube").setup({})
require("kubectl")
_G.kube.context = CONTEXT

---Run kubectl in the test namespace.
---@param args string[]
---@return vim.SystemCompleted
local function k(args)
  return vim.system(vim.list_extend({ "kubectl", "--context", CONTEXT, "-n", NS }, args), { text = true }):wait(30000)
end

---@param args string[]
---@return string
local function jsonpath(args)
  return vim.trim(k(args).stdout or "")
end

-- Reset what the tests change, so that they can be rerun on the same cluster
assert(k({ "scale", "deployment/web", "--replicas=1" }).code == 0)
assert(k({ "rollout", "status", "deployment/web", "--timeout=120s" }).code == 0)
assert(vim
  .system({ "kubectl", "--context", CONTEXT, "-n", NS, "replace", "-f", "-" }, {
    stdin = vim.json.encode({
      apiVersion = "v1",
      kind = "Secret",
      metadata = { name = "db", namespace = NS },
      stringData = { username = "admin", password = "s3cret" },
    }),
  })
  :wait(30000).code == 0)

local CHART = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/chart"

---Run helm in the test namespace.
---@param args string[]
---@return vim.SystemCompleted
local function h(args)
  return vim.system(vim.list_extend({ "helm", "--kube-context", CONTEXT, "-n", NS }, args), { text = true }):wait(60000)
end

-- A release with two revisions
assert(h({ "uninstall", "greeter", "--ignore-not-found", "--wait" }).code == 0)
assert(h({ "install", "greeter", CHART }).code == 0)
assert(h({ "upgrade", "greeter", CHART, "--set", "greeting=hi" }).code == 0)

---@param kind string
---@return string
local function list(kind)
  return string.format("kube://context/%s/namespaces/%s/%s", CONTEXT, NS, kind)
end

---@param name string
local function open(name)
  vim.cmd.edit(vim.fn.fnameescape(name))
  t.wait_loaded(TIMEOUT)
end

---@param pattern string Lua pattern
---@return string
local function wait_line(pattern)
  local found
  t.wait_for(function()
    for _, line in ipairs(t.lines()) do
      if line:find(pattern) then
        found = line
        return true
      end
    end
  end, "a line matching " .. pattern .. " in " .. vim.api.nvim_buf_get_name(0), TIMEOUT)
  return found
end

---@param title string
local function code_action(title)
  t.wait_for(function()
    local client = vim.lsp.get_clients({ bufnr = 0, name = "kube" })[1]
    return client and client.initialized
  end, "the kube language server")
  local applied = false
  vim.lsp.buf.code_action({
    filter = function(action)
      applied = applied or action.title == title
      return action.title == title
    end,
    apply = true,
  })
  t.wait_for(function()
    return applied
  end, "code action " .. title)
end

local function answer_yes()
  t.answer_prompts(function(items)
    return vim.tbl_contains(items, "Yes") and "Yes" or items[1]
  end)
end

after_each(function()
  t.restore_stubs()
  t.clean_buffers()
end)

describe("kind cluster", function()
  it("lists pods", function()
    open(list("pods"))
    t.ok(wait_line("^kube%-e2e%s+web%-.-Running"))
    t.ok(wait_line("^kube%-e2e%s+logger%-.-Running"))
  end)

  it("describes in a hover", function()
    open(list("pods"))
    t.press_on("web-", "K")
    t.wait_for(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
        if vim.api.nvim_win_get_config(win).relative ~= "" and text:find("Namespace:%s+kube%-e2e") then
          return true
        end
      end
    end, "hover", TIMEOUT)
  end)

  it("shows and follows logs", function()
    open(list("pods"))
    t.press_on("logger-", "gl")
    wait_line("^log%-line%-%d+$")

    open(list("pods"))
    t.press_on("logger-", "gL")
    wait_line("^log%-line%-%d+$")
    local count = #t.lines()
    t.wait_for(function()
      return #t.lines() > count
    end, "new log lines", TIMEOUT)
    vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "mx", false)
  end)

  it("applies edited YAML after showing the diff", function()
    open(list("deployments"))
    t.press_on("web", "gd")
    t.wait_loaded(TIMEOUT)
    local lnum = vim.fn.search("^  replicas: 1$", "cw")
    t.ok(lnum > 0, "spec.replicas")
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { "  replicas: 2" })

    local diff
    t.answer_prompts(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "diff" then
          diff = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        end
      end
      return "Yes"
    end)
    vim.cmd.write()
    t.wait_for(function()
      return jsonpath({ "get", "deployment", "web", "-o", "jsonpath={.spec.replicas}" }) == "2"
    end, "replicas to be 2", TIMEOUT)
    t.ok(diff and diff:find("+  replicas: 2", 1, true), diff)
  end)

  it("scales and restarts with code actions", function()
    open(list("deployments"))
    t.answer_prompts(nil, "1")
    t.press_on("web", "")
    code_action("Scale…")
    t.wait_for(function()
      return jsonpath({ "get", "deployment", "web", "-o", "jsonpath={.spec.replicas}" }) == "1"
    end, "replicas to be 1", TIMEOUT)

    answer_yes()
    t.press_on("web", "")
    code_action("Restart")
    t.wait_for(function()
      local annotation = "jsonpath={.spec.template.metadata.annotations.kubectl\\.kubernetes\\.io/restartedAt}"
      return jsonpath({ "get", "deployment", "web", "-o", annotation }) ~= ""
    end, "restart annotation", TIMEOUT)
    t.ok(k({ "rollout", "status", "deployment/web", "--timeout=120s" }).code == 0, "rollout after restart")
  end)

  it("scales by editing the DESIRED cell", function()
    open(list("deployments"))
    answer_yes()
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    for id, cell in pairs(kbuf.mark_columns) do
      if cell.column == "DESIRED" and cell.item.metadata.name == "web" then
        local mark = vim.api.nvim_buf_get_extmark_by_id(0, require("kube.constants").KUBE_COLUMN_NAMESPACE, id, {})
        vim.api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
      end
    end
    vim.api.nvim_feedkeys(vim.keycode("ciw2<Esc>"), "mx", false)
    vim.cmd.write()
    t.wait_for(function()
      return jsonpath({ "get", "deployment", "web", "-o", "jsonpath={.spec.replicas}" }) == "2"
    end, "replicas to be 2", TIMEOUT)
  end)

  it("decodes and updates secrets", function()
    open(list("secrets"))
    t.press_on("db", "<CR>")
    t.wait_loaded(TIMEOUT)
    wait_line('^username: "admin"$')
    wait_line('^password: "s3cret"$')

    local lnum = vim.fn.search('^username: "admin"$', "cw")
    vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { 'username: "root"' })
    answer_yes()
    vim.cmd.write()
    t.wait_for(function()
      local encoded = jsonpath({ "get", "secret", "db", "-o", "jsonpath={.data.username}" })
      return encoded ~= "" and vim.base64.decode(encoded) == "root"
    end, "username to be root", TIMEOUT)
  end)

  it("lists events", function()
    open(list("events"))
    wait_line("^kube%-e2e%s+")
  end)

  it("shows the events of a deployment and its pods", function()
    open(list("deployments"))
    t.press_on("web", "")
    code_action("Show events")
    -- The restart above created pods, whose events belong to the deployment's
    wait_line("Scheduled%s+pod/web%-")
  end)

  it("forwards ports", function()
    open(list("services"))
    local asked = false
    t.answer_prompts(function(items)
      if asked then
        return nil
      end
      asked = true
      return items[1]
    end, "18080")
    t.press_on("web", "gf")
    t.wait_for(function()
      local out = vim.system({ "curl", "-s", "http://localhost:18080" }, { text = true }):wait(5000)
      return out.code == 0 and out.stdout:find("nginx", 1, true)
    end, "nginx through the port forward", TIMEOUT)
    for _, forwards in pairs(_G.portforwards) do
      for _, forward in pairs(forwards) do
        require("kubectl").kill(forward.job)
      end
    end
  end)

  it("execs into a container", function()
    open(list("pods"))
    -- Not a pod still terminating after the restart
    local pod = wait_line("^kube%-e2e%s+web%-%S+%s+1/1%s+Running"):match("^kube%-e2e%s+(%S+)")
    t.press_on(pod, "gs")
    local channel = vim.bo.channel
    t.ok(channel > 0, "terminal job")
    vim.fn.chansend(channel, "echo e2e-$((40+2))\n")
    t.wait_for(function()
      return table.concat(t.lines(), "\n"):find("e2e%-42")
    end, "exec output", TIMEOUT)
    vim.fn.chansend(channel, "exit\n")
  end)

  it("deletes a pod by deleting its line", function()
    open(list("pods"))
    local line = wait_line("^kube%-e2e%s+logger%-")
    local pod = line:match("^kube%-e2e%s+(%S+)")
    answer_yes()
    t.press_on(pod, "dd")
    vim.cmd.write()
    t.wait_for(function()
      return k({ "get", "pod", pod }).code ~= 0
    end, "pod " .. pod .. " to be deleted", TIMEOUT * 2)
  end)
end)

describe("helm releases", function()
  local RELEASE = list("helm-releases") .. "/greeter"

  it("lists releases, <CR> shows the manifest, gd the values", function()
    open(list("helm-releases"))
    wait_line("^kube%-e2e%s+greeter%s+2%s+deployed%s+kube%-e2e%-0%.1%.0%s+1%.0")
    t.press_on("greeter", "<CR>")
    wait_line('greeting: "hi"')
    t.eq(RELEASE .. "/manifest", vim.api.nvim_buf_get_name(0))

    open(list("helm-releases"))
    t.press_on("greeter", "gd")
    wait_line("^greeting: hi$")
  end)

  it("rolls back to a revision of the history", function()
    open(RELEASE .. "/history")
    wait_line("^2%s.-deployed")
    answer_yes()
    t.press_on("Install complete", "")
    code_action("Rollback to revision 1")
    t.wait_for(function()
      local history = vim.json.decode(h({ "history", "greeter", "-o", "json" }).stdout)
      return history[3] and history[3].description == "Rollback to 1"
    end, "revision 3 rolling back to 1", TIMEOUT)
  end)

  it("uninstalls a release by deleting its line", function()
    open(list("helm-releases"))
    wait_line("greeter")
    answer_yes()
    t.press_on("greeter", "dd")
    vim.cmd.write()
    t.wait_for(function()
      return h({ "status", "greeter" }).code ~= 0
    end, "release greeter to be uninstalled", TIMEOUT)
  end)
end)
