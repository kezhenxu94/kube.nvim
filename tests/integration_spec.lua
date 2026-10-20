local constants = require("kube.constants")
local t = require("helpers")
local utils = require("kube.utils")

require("kube").setup({})
require("kubectl")

---@param name string
local function open(name)
  vim.cmd.edit(vim.fn.fnameescape(name))
  t.wait_loaded()
end

local function buf_name()
  return vim.api.nvim_buf_get_name(0)
end

---@param pattern string Lua pattern
local function wait_call(pattern)
  t.wait_for(function()
    return #t.calls_matching(pattern) > 0
  end, "kubectl call matching " .. pattern)
end

---@param name string
local function wait_buf_name(name)
  t.wait_for(function()
    return buf_name() == name
  end, "buffer " .. name .. ", current: " .. buf_name())
end

---@param text string
---@return integer win The floating window showing text
local function wait_float(text)
  local found
  t.wait_for(function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      if vim.api.nvim_win_get_config(win).relative ~= "" and table.concat(lines, "\n"):find(text, 1, true) then
        found = win
        return true
      end
    end
  end, "a float with " .. text)
  return found
end
local PODS = "kube://context/ctx-a/namespaces/ns1/pods"

before_each(function()
  t.reset_kubectl()
  _G.kube.context = nil
  t.respond("*config current-context*", { stdout = "ctx-a\n" })
  t.respond("*get pods -o json*", { fixture = "pods.json" })
  t.respond("*get pod -o json web-1 *", { fixture = "pod-web-1.json" })
  t.respond("*get deployments -o json*", { fixture = "deployments.json" })
  t.respond("*get deployment.apps web -o yaml*", { fixture = "deployment-web.yaml" })
  t.respond("*describe*", { stdout = "Name: web" })
  t.respond("*logs*", { stdout = "line1\nline2\n" })
  t.capture_notify()
end)

after_each(function()
  t.restore_stubs()
  t.clean_buffers()
  for _, forwards in pairs(_G.portforwards) do
    for _, forward in pairs(forwards) do
      require("kubectl").kill(forward.job)
    end
  end
  _G.portforwards = {}
end)

describe("opening buffers", function()
  it(":Kube get pins the current context and renders the resources", function()
    vim.cmd("Kube get pods namespace=ns1 selector=app=web")
    t.wait_loaded()

    t.eq(PODS .. "?selector=app=web", buf_name())
    t.eq({ "--context ctx-a get pods -o json -n ns1 --selector=app=web" }, t.calls_matching("get pods"))
    local lines = t.lines()
    t.eq(2, #lines)
    t.ok(lines[1]:match("^ns1%s+web%-1%s+2/2%s+Running"), lines[1])
    t.ok(lines[2]:match("^ns1%s+web%-2%s+0/1%s+Pending"), lines[2])
    t.eq("acwrite", vim.bo.buftype)
  end)

  it("publishes diagnostics for unhealthy resources", function()
    open("kube://pods")
    local diagnostics = vim.diagnostic.get(0)
    t.eq(1, #diagnostics)
    t.eq(1, diagnostics[1].lnum)
  end)

  it("reuses the pinned buffer when the shorthand is opened again", function()
    open("kube://namespaces/ns1/pods")
    local first = vim.api.nvim_get_current_buf()
    vim.cmd.enew()
    vim.cmd.edit("kube://namespaces/ns1/pods")
    t.wait_for(function()
      return vim.api.nvim_get_current_buf() == first
    end, "switch to the existing buffer")
    vim.wait(50)

    t.eq(PODS, buf_name())
    t.eq(1, #t.calls_matching("get pods"))
    t.eq(0, #vim.tbl_filter(function(buf)
      return vim.api.nvim_buf_get_name(buf) == "kube://namespaces/ns1/pods"
    end, vim.api.nvim_list_bufs()))
  end)

  it("uses an explicit context without asking for the current one", function()
    open("kube://context/ctx-b/pods")
    t.eq({ "--context ctx-b get pods -o json --all-namespaces" }, t.calls_matching(" get "))
  end)

  it("encodes contexts with / and :", function()
    _G.kube.context = "arn:aws:eks:r:1:cluster/prod"
    vim.cmd("Kube get pods")
    t.wait_loaded()
    t.eq("kube://context/arn%3aaws%3aeks%3ar%3a1%3acluster%2fprod/pods", buf_name())
    t.eq(1, #t.calls_matching("^%-%-context arn:aws:eks:r:1:cluster/prod get pods"))
  end)

  it("reports a missing current context", function()
    local messages = t.capture_notify()
    t.respond("*config current-context*", { stderr = "error: current-context is not set", code = 1 })
    vim.cmd.edit("kube://pods")
    t.eq("No current kubectl context", messages[1].msg)
    t.eq(nil, _G.kube_buffers[vim.api.nvim_get_current_buf()])
  end)
end)

describe("context pinning", function()
  it("keeps operating on the buffer's context after switching", function()
    open("kube://namespaces/ns1/pods")
    local pinned = vim.api.nvim_get_current_buf()
    vim.cmd("Kube context ctx-b")

    t.press_on("web-1", "R")
    t.wait_loaded()
    t.eq(2, #t.calls_matching("^%-%-context ctx%-a get pods"))
    t.eq(0, #t.calls_matching("ctx%-b"))

    t.respond("*delete*", { stdout = "deleted" })
    t.answer_prompts(function()
      return "Yes"
    end)
    t.press_on("web-2", "dd")
    vim.cmd.write()
    wait_call("delete")
    t.eq({ "--context ctx-a delete pod web-2 -n ns1" }, t.calls_matching("delete"))

    vim.cmd("Kube get pods namespace=ns1")
    t.wait_loaded()
    t.eq("kube://context/ctx-b/namespaces/ns1/pods", buf_name())
    t.ok(vim.api.nvim_get_current_buf() ~= pinned)
  end)

  it("edits the pinned buffer for a name without context, leaving no alias behind", function()
    open("kube://context/ctx-a/namespaces/ns1/deployments")
    local deployments = vim.api.nvim_get_current_buf()
    open("kube://namespaces/ns1/pods")
    local pods = vim.api.nvim_get_current_buf()
    t.eq("kube://context/ctx-a/namespaces/ns1/pods", buf_name())
    t.eq(deployments, vim.fn.bufnr("#"))

    vim.cmd.edit("kube://context/ctx-a/namespaces/ns1/deployments")
    vim.cmd.edit("kube://namespaces/ns1/pods")
    t.eq(pods, vim.api.nvim_get_current_buf(), "the existing pinned buffer")
    t.eq(deployments, vim.fn.bufnr("#"))
    vim.wait(20)
    t.eq(-1, vim.fn.bufnr("^kube://namespaces/ns1/pods$"), "the alias is wiped")

    vim.cmd("normal! \15")
    t.eq(deployments, vim.api.nvim_get_current_buf(), "<C-o> goes back")
  end)
end)

describe("ns", function()
  it("opens the same buffer as namespaces", function()
    open("kube://namespaces/ns1/pods")
    local pods = vim.api.nvim_get_current_buf()
    open("kube://ns/ns1/deployments")
    t.eq("kube://context/ctx-a/namespaces/ns1/deployments", buf_name())
    vim.cmd.edit("kube://context/ctx-a/ns/ns1/pods")
    t.eq(pods, vim.api.nvim_get_current_buf())
  end)
end)

describe("resource under the cursor", function()
  it("follows the latest render after a refresh", function()
    open("kube://namespaces/ns1/pods")
    t.respond("*get pods -o json*", { fixture = "pods-reversed.json" })
    t.press_on("web-1", "R")
    t.wait_loaded()
    t.ok(t.lines()[1]:find("web-2", 1, true), "list is reordered")

    vim.api.nvim_win_set_cursor(0, { 1, assert(t.lines()[1]:find("web-2", 1, true)) - 1 })
    vim.api.nvim_feedkeys("gd", "mx", false)
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-2?output=yaml")
  end)

  it("keeps the cursor on the same resource when reloading", function()
    open("kube://namespaces/ns1/pods")
    vim.api.nvim_win_set_cursor(0, { 2, 7 })
    t.respond("*get pods -o json*", { fixture = "pods-reversed.json" })
    vim.api.nvim_feedkeys("R", "mx", false)
    t.wait_loaded()
    t.ok(t.lines()[1]:find("web-2", 1, true), "list is reordered")
    t.eq({ 1, 7 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("keeps the cursor line when its resource is gone", function()
    open("kube://namespaces/ns1/pods")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local only_web_1 = vim.json.decode(t.fixture("pods.json"))
    only_web_1.items = { only_web_1.items[1] }
    t.respond("*get pods -o json*", { stdout = vim.json.encode(only_web_1) })
    vim.api.nvim_feedkeys("R", "mx", false)
    t.wait_loaded()
    t.eq(1, #t.lines())
    t.eq(1, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("ignores lines without a resource", function()
    open("kube://namespaces/ns1/pods")
    vim.cmd("normal! Go")
    vim.api.nvim_feedkeys(vim.keycode("<Esc>K"), "mx", false)
    t.eq(PODS, buf_name())
  end)
end)

describe("actions", function()
  it("drills down from a pod to its containers", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()
    t.eq(1, #t.calls_matching("^%-%-context ctx%-a get pod %-o json web%-1 %-n ns1$"))
    t.ok(t.lines()[1]:match("^init%s+init%s+Completed%s+0%s+busybox:1"), t.lines()[1])
    t.ok(t.lines()[2]:match("^app%s+main%s+Running%s+1%s+web:1%s+8080/TCP, 9090/TCP"), t.lines()[2])
    t.ok(t.lines()[3]:match("^sidecar"), t.lines()[3])
  end)

  it("drills down from a deployment to its pods", function()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "<CR>")
    wait_buf_name(PODS .. "?selector=app=web,tier=frontend")
    t.wait_loaded()
    t.eq(1, #t.calls_matching("get pods .*%-%-selector=app=web,tier=frontend$"))
  end)

  it("K describes in a hover with the group-qualified type", function()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "K")
    local float = wait_float("Name: web")
    t.eq({ "--context ctx-a describe deployment.apps web -n ns1" }, t.calls_matching("describe"))
    vim.api.nvim_win_close(float, true)
  end)

  it("goes to the editable YAML definition", function()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "gd")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    t.wait_loaded()
    t.eq("kind: Deployment", t.lines()[2])
    t.eq("yaml", vim.bo.filetype)
    t.eq(true, vim.bo.modifiable)

    -- Nothing to apply without changes
    vim.cmd.write()
    vim.wait(100)
    t.eq({}, t.calls_matching("apply"))
  end)

  it("keeps the YAML read-only when it cannot be loaded", function()
    t.respond("*get deployment.apps web -o yaml*", { stderr = "forbidden", code = 1 })
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "gd")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    t.wait_loaded()
    t.eq({ "" }, t.lines())
    t.eq(false, vim.bo.modifiable)
    t.eq("✗ forbidden", t.status())
  end)

  it("opens port forward URLs with gx", function()
    t.respond("*port-forward*", { script = "sleep 30" })
    local asked = false
    t.answer_prompts(function(items)
      if asked then
        return nil
      end
      asked = true
      return items[1]
    end, "18080")
    local opened
    t.stub(vim.ui, "open", function(url)
      opened = url
      return nil, nil
    end)
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gf")
    t.press_on("web-1", "gF")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/portforward")
    t.wait_loaded()
    t.press_on("http://localhost:18080", "gx")
    t.wait_for(function()
      return opened
    end, "gx to open the URL")
    t.eq("http://localhost:18080", opened)
  end)

  it("shows pod logs", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gl")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs")
    t.wait_for(function()
      return t.lines()[1] == "line1"
    end, "logs")
    t.eq({ "line1", "line2" }, t.lines())
    t.eq({ "--context ctx-a logs pod/web-1 -n ns1 --tail=1000" }, t.calls_matching("logs"))
  end)

  it("logs can be edited, :w keeps the edits and :e reloads", function()
    t.respond("*logs*", { stdout = "a\\tb\n" })
    vim.cmd.edit("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs")
    t.wait_loaded()
    t.eq({ "a\\tb" }, t.lines())
    vim.cmd([[%s/\\t/\t/g]])
    t.eq({ "a\tb" }, t.lines())
    t.ok(not pcall(vim.cmd.write), ":w fails instead of reloading")
    t.eq({ "a\tb" }, t.lines())
    t.eq(1, #t.calls_matching("logs"))
    t.eq(false, vim.bo.modified, "edits do not block quitting")

    local file = vim.fn.tempname()
    vim.cmd.write(file)
    t.eq({ "a\tb" }, vim.fn.readfile(file))

    vim.cmd.edit()
    t.wait_loaded()
    t.eq({ "a\\tb" }, t.lines())
    t.eq(true, vim.bo.modifiable)
  end)

  it("shows container logs", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()
    t.press_on("sidecar", "gl")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?container=sidecar")
    wait_call("logs")
    t.eq({ "--context ctx-a logs pod/web-1 -c sidecar -n ns1 --tail=1000" }, t.calls_matching("logs"))
  end)

  it("follows logs and stops on <C-c>", function()
    t.respond("*logs*", { script = "printf 'a\\nb\\n'; sleep 30" })
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gL")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true")
    t.wait_for(function()
      return t.lines()[1] == "a"
    end, "streamed logs")
    t.eq({ "a", "b", "" }, t.lines())

    local function status()
      local marks = vim.api.nvim_buf_get_extmarks(0, constants.KUBE_NAMESPACE, 0, -1, { details = true })
      t.eq(1, #marks, "a single status mark")
      return marks[1][4].virt_text[1][1]
    end
    t.ok(status():find("Waiting for new logs", 1, true))

    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    local job = kbuf.loading_job
    vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "mx", false)
    t.wait_for(function()
      return job:is_closing()
    end, "logs job to stop")
    t.ok(status():find("Stopped following logs", 1, true))
  end)

  it("execs into the selected container in the buffer's context", function()
    local cmd
    t.stub(vim.fn, "jobstart", function(c)
      cmd = c
      return 1
    end)
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()
    t.press_on("app", "gs")
    vim.cmd.stopinsert()

    t.eq("kube://context/ctx-a/namespaces/ns1/pod/web-1/exec?container=app", buf_name())
    t.eq(
      { "kubectl", "--context", "ctx-a", "exec", "-it", "pod/web-1", "-n", "ns1", "-c", "app", "--" },
      vim.list_slice(cmd, 1, 11)
    )
  end)

  it("starts the shell from the buffer name, and reuses it", function()
    t.respond("*exec*", { script = "sleep 30" })
    local name = "kube://context/ctx-a/namespaces/ns1/pod/web-1/exec?container=app"
    open("kube://namespaces/ns1/pods")
    local pods = vim.api.nvim_get_current_buf()
    vim.cmd.edit(vim.fn.fnameescape(name))
    wait_call("exec")
    t.eq(
      { "--context ctx-a exec -it pod/web-1 -n ns1 -c app -- sh -c command -v bash >/dev/null && exec bash || exec sh" },
      t.calls_matching("exec %-it")
    )
    t.eq("terminal", vim.bo.buftype)
    t.eq(name, buf_name())
    t.eq(pods, vim.fn.bufnr("#"))
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      t.ok(not vim.startswith(vim.api.nvim_buf_get_name(buf), "term://"), "no term:// buffer left")
    end
    local shell = vim.api.nvim_get_current_buf()

    t.answer_prompts(function(items)
      return items[1]
    end)
    open("kube://ns/ns1/pods")
    t.press_on("web-1", "gs")
    vim.cmd.stopinsert()
    t.eq(shell, vim.api.nvim_get_current_buf(), "the running shell")
    t.eq(1, #t.calls_matching("exec %-it"))
  end)

  it("prompts for the container to exec into", function()
    local cmd
    t.stub(vim.fn, "jobstart", function(c)
      cmd = c
      return 1
    end)
    local offered
    t.answer_prompts(function(items, opts)
      offered = vim.tbl_map(opts.format_item, items)
      return items[2]
    end)
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gs")
    vim.cmd.stopinsert()
    t.eq({ "app", "sidecar" }, offered)
    t.eq({ "-c", "sidecar" }, vim.list_slice(cmd, 9, 10))
  end)

  it("sets the image and reloads", function()
    t.respond("*set image*", { stdout = "updated" })
    local asked = 0
    t.answer_prompts(function(items)
      asked = asked + 1
      return items[1]
    end, "web:2")
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "gi")
    wait_call("set image")
    t.eq({ "--context ctx-a set image deployment.apps/web app=web:2 -n ns1" }, t.calls_matching("set image"))
    t.wait_for(function()
      return #t.calls_matching("get deployments") == 2
    end, "reload")
    t.eq(1, asked)
  end)

  it("warns about unsupported actions instead of failing", function()
    local messages = t.capture_notify()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()
    t.press_on("app", "gi")
    t.eq({ msg = "set_image is not supported for containers", level = vim.log.levels.WARN }, messages[#messages])
  end)

  it("shows the help with the configured keymaps", function()
    open("kube://namespaces/ns1/pods")
    local kube_win = vim.api.nvim_get_current_win()
    vim.api.nvim_feedkeys("g?", "mx", false)
    local help_win = vim.api.nvim_get_current_win()
    t.ok(help_win ~= kube_win, "help window is focused")
    t.eq("editor", vim.api.nvim_win_get_config(help_win).relative)
    local text = table.concat(t.lines(), "\n")
    t.ok(text:find("g?       show this help", 1, true), text)
    t.ok(text:find("K        describe the resource under the cursor", 1, true), text)
    t.ok(text:find(":Kube get {kind}", 1, true), text)
    vim.api.nvim_feedkeys("q", "mx", false)
    t.eq(kube_win, vim.api.nvim_get_current_win())
  end)
end)

describe("navigation", function()
  before_each(function()
    t.respond("*get namespaces -o json*", { fixture = "namespaces.json" })
    t.respond("*api-resources*", { fixture = "api-resources.txt" })
    t.respond("*get pod -o json --all-namespaces*", { fixture = "pods.json" })
    t.respond("*get pod -o json -n ns1*", { fixture = "pods.json" })
    t.respond("*get deployment.apps -o json -n ns1*", { fixture = "deployments.json" })
  end)

  it("- goes up to the parent until the namespaces", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()

    for _, parent in ipairs({
      "kube://context/ctx-a/namespaces/ns1/pod",
      "kube://context/ctx-a/pod",
      "kube://context/ctx-a/namespaces",
      "kube://context/ctx-a/api-resources",
    }) do
      vim.api.nvim_feedkeys("-", "mx", false)
      wait_buf_name(parent)
      t.wait_loaded()
    end

    vim.api.nvim_feedkeys("-", "mx", false)
    t.eq("kube://context/ctx-a/api-resources", buf_name(), "the resource types have no parent")
  end)

  it("kube:// lists the resource types, which open their list", function()
    open("kube://")
    t.eq("kube://context/ctx-a/api-resources", buf_name())
    t.eq("bindings                 v1                      true        Binding   ", t.lines()[1], "empty SHORTNAMES")
    t.eq("deployments  deploy      apps/v1                 true        Deployment", t.lines()[5])
    t.press_on("deployments", "<CR>")
    wait_buf_name("kube://context/ctx-a/deployments.apps")
  end)

  it("opens namespaced resource types in the namespace of the list", function()
    open("kube://ns/ns1/api-resources")
    t.press_on("deployments", "<C-]>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployments.apps")
    vim.cmd("normal! \20")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/api-resources")
    t.press_on("nodes", "gd")
    wait_buf_name("kube://context/ctx-a/nodes")
  end)

  it("K explains the resource type in a hover", function()
    t.respond("*explain*", { stdout = "GROUP:      apps\nKIND:       Deployment" })
    open("kube://")
    t.press_on("deployments", "K")
    local float = wait_float("KIND:       Deployment")
    t.eq({ "--context ctx-a explain deployments.apps" }, t.calls_matching("explain"))
    vim.api.nvim_win_close(float, true)
  end)

  it("lists the resource types of the API groups that answer", function()
    local messages = t.capture_notify()
    local fixture = vim.fn.fnamemodify("tests/fixtures/api-resources.txt", ":p")
    t.respond("*api-resources*", {
      script = string.format(
        "cat '%s'; echo 'error: unable to retrieve the complete list of server APIs: metrics.k8s.io/v1beta1' >&2; exit 1",
        fixture
      ),
    })
    open("kube://")
    t.ok(table.concat(t.lines(), "\n"):find("deployments", 1, true))
    t.ok(t.status():find("metrics.k8s.io", 1, true), t.status())
    t.eq(vim.log.levels.ERROR, messages[#messages].level)
  end)

  it("- from a definition lists the kind with its formatter", function()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "gd")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    t.wait_loaded()
    vim.api.nvim_feedkeys("-", "mx", false)
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps")
    t.wait_loaded()
    t.ok(t.lines()[1]:match("^ns1%s+web%s+1/2"), t.lines()[1])
  end)

  it("- keeps the selector when leaving the namespace", function()
    open("kube://namespaces/ns1/pods?selector=app=web")
    vim.api.nvim_feedkeys("-", "mx", false)
    wait_buf_name("kube://context/ctx-a/pods?selector=app=web")
  end)

  it("<C-]> on a namespace filters the list, <C-t> goes back", function()
    open("kube://pods?selector=app=web")
    local list = vim.api.nvim_get_current_buf()
    t.press_on("ns1", "<C-]>")
    wait_buf_name(PODS .. "?selector=app=web")
    t.wait_loaded()
    t.eq(1, #t.calls_matching("get pods %-o json %-n ns1 %-%-selector=app=web$"))

    vim.api.nvim_feedkeys(vim.keycode("<C-t>"), "mx", false)
    t.eq(list, vim.api.nvim_get_current_buf())
  end)

  it("<C-]> on a node opens the node", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("node-1", "<C-]>")
    wait_buf_name("kube://context/ctx-a/node/node-1")
    wait_call("describe")
    t.eq({ "--context ctx-a describe node node-1" }, t.calls_matching("describe"))
  end)

  it("gd jumps like <C-]>", function()
    open("kube://pods")
    t.press_on("ns1", "gd")
    wait_buf_name(PODS)
  end)

  it("<C-]> elsewhere goes to the definition", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("Running", "<C-]>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml")
  end)

  it("<C-]> on a namespace row lists its pods", function()
    open("kube://namespaces")
    t.press_on("ns2", "<C-]>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns2/pods")
  end)

  it("<C-w>] opens the jump in a split", function()
    open("kube://pods")
    t.press_on("ns1", "<C-w>]")
    wait_buf_name(PODS)
    t.eq(2, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("<C-]> resolves cells by their exact columns", function()
    open("kube://namespaces/ns1/pods")
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    local navigation = require("kube.navigation")
    local node_col = assert(t.lines()[1]:find("node-1", 1, true)) - 1
    local definition = "kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml"

    t.eq("kube://context/ctx-a/node/node-1", navigation.tag_target(kbuf, { 0, node_col }), "first char of NODE")
    t.eq("kube://context/ctx-a/node/node-1", navigation.tag_target(kbuf, { 0, node_col + 5 }), "last char of NODE")
    t.eq(definition, navigation.tag_target(kbuf, { 0, node_col - 1 }), "column separator")
    t.eq(definition, navigation.tag_target(kbuf, { 0, node_col - 3 }), "last char of IP")
  end)

  it("<C-]> on a row without a resource reports no tag", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "<CR>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers")
    t.wait_loaded()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local ok, err = pcall(vim.cmd, "normal! \29")
    t.ok(not ok and err:find("E426", 1, true), tostring(err))
    t.eq("kube://context/ctx-a/namespaces/ns1/pod/web-1/containers", buf_name())
  end)
end)

describe("editing YAML", function()
  local EDIT = "kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml"

  local function open_edit()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "gd")
    wait_buf_name(EDIT)
    t.wait_loaded()
    t.eq(true, vim.bo.modifiable)
  end

  before_each(function()
    t.respond("*diff*", { stdout = "-  replicas: 2\n+  replicas: 3\n", code = 1 })
    t.answer_prompts(function()
      return "Yes"
    end)
  end)

  it("applies once per save, however often the buffer was refreshed", function()
    t.respond("*apply*", { stdout = "configured" })
    open_edit()
    for _ = 1, 2 do
      vim.api.nvim_feedkeys("R", "mx", false)
      t.wait_loaded()
    end

    vim.api.nvim_buf_set_lines(0, 5, 6, false, { "  replicas: 3" })
    vim.cmd.write()
    wait_call("apply")
    t.wait_for(function()
      return #t.calls_matching("%-o yaml") == 4
    end, "reload after apply")

    t.eq(1, #t.calls_matching("^%-%-context ctx%-a %-n ns1 apply %-f "))
    t.wait_for(function()
      return not vim.bo.modified
    end, "reloaded buffer to be unmodified")
  end)

  it("keeps the edits when apply fails", function()
    local messages = t.capture_notify()
    t.respond("*apply*", { stderr = "admission denied", code = 1 })
    open_edit()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 5, 6, false, { "  replicas: 3" })

    vim.cmd.write()
    wait_call("apply")
    t.wait_for(function()
      return #messages > 0 and messages[#messages].msg:find("admission denied", 1, true)
    end, "error notification")
    vim.wait(50)

    t.ok(vim.api.nvim_buf_is_valid(buf), "buffer is kept")
    t.eq("  replicas: 3", vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1])
    t.eq(true, vim.bo[buf].modified)
    t.eq(1, #t.calls_matching("%-o yaml"), "not reloaded")
  end)
end)

describe("deleting by editing the list", function()
  it("deletes all deleted rows after one confirmation", function()
    t.respond("*delete*", { stdout = "deleted" })
    local seen = {}
    t.answer_prompts(function(_, opts)
      table.insert(seen, opts.prompt)
      return "Yes"
    end)
    open("kube://namespaces/ns1/pods")
    vim.cmd("normal! ggdG")
    vim.cmd.write()
    t.wait_for(function()
      return #t.calls_matching("delete") == 2 and #t.calls_matching("get pods") == 2
    end, "deletes and reload")
    local deletes = t.calls_matching("delete")
    table.sort(deletes)
    t.eq({ "--context ctx-a delete pod web-1 -n ns1", "--context ctx-a delete pod web-2 -n ns1" }, deletes)
    t.eq({ "Apply the changes (context: ctx-a)?\n  Delete pod: ns1/web-1\n  Delete pod: ns1/web-2" }, seen)
  end)

  it("deletes nothing when cancelled", function()
    t.answer_prompts(function()
      return "No"
    end)
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "dd")
    vim.cmd.write()
    vim.wait(100)
    t.eq({}, t.calls_matching("delete"))
    t.eq(true, vim.bo.modified)
  end)
end)

describe("port forwarding", function()
  local key = utils.portforward_key("ctx-a", "ns1", "pod", "web-1")

  ---Forward the n-th port of web-1 to local_port.
  local function forward(choice, local_port)
    local asked = false
    t.answer_prompts(function(items)
      if asked then
        return nil
      end
      asked = true
      return items[choice]
    end, tostring(local_port))
    t.press_on("web-1", "gf")
    t.wait_for(function()
      return _G.portforwards[key] and _G.portforwards[key][local_port]
    end, "port forward " .. local_port)
  end

  before_each(function()
    t.respond("*port-forward*", { script = "sleep 30" })
  end)

  it("forwards the selected port in the buffer's context", function()
    open("kube://namespaces/ns1/pods")
    forward(2, 19090)
    wait_call("port%-forward")
    t.eq({ "--context ctx-a port-forward pod/web-1 19090:9090 -n ns1" }, t.calls_matching("port%-forward"))
    t.eq(9090, _G.portforwards[key][19090].container_port)
  end)

  it("lists forwards and stops only the deleted one", function()
    open("kube://namespaces/ns1/pods")
    forward(1, 18080)
    forward(2, 19090)
    wait_call("port%-forward")
    local job_18080 = _G.portforwards[key][18080].job
    local job_19090 = _G.portforwards[key][19090].job

    t.press_on("web-1", "gF")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/portforward")
    t.wait_loaded()
    t.eq(2, #t.lines())
    t.ok(t.lines()[1]:find("http://localhost:18080", 1, true), t.lines()[1])

    t.answer_prompts(function()
      return "Yes"
    end)
    t.press_on("http://localhost:18080", "dd")
    vim.cmd.write()
    t.wait_for(function()
      return job_18080:is_closing()
    end, "forward to stop")
    t.wait_for(function()
      return #t.lines() == 1 and t.lines()[1]:find("http://localhost:19090", 1, true)
    end, "reload")

    t.eq(nil, _G.portforwards[key][18080])
    t.ok(_G.portforwards[key][19090], "other forward is kept")
    t.eq(false, job_19090:is_closing())
  end)

  it("rejects a local port that is already forwarded", function()
    local messages = t.capture_notify()
    open("kube://namespaces/ns1/pods")
    forward(1, 18080)
    wait_call("port%-forward")
    forward(1, 18080)
    t.eq(1, #t.calls_matching("port%-forward"))
    t.ok(vim.tbl_contains(
      vim.tbl_map(function(m)
        return m.msg
      end, messages),
      "Local port 18080 is already used"
    ))
  end)
end)

describe("cleanup", function()
  it("stops the jobs of an unloaded buffer and loads it again when edited", function()
    t.respond("*logs*", { script = "sleep 30" })
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gL")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true")
    local buf = vim.api.nvim_get_current_buf()
    local kbuf = _G.kube_buffers[buf]
    local job = kbuf.loading_job

    vim.cmd("bunload! " .. buf)
    t.wait_for(function()
      return job:is_closing()
    end, "job to stop")
    t.eq(kbuf, _G.kube_buffers[buf], "the state is kept")

    vim.cmd.buffer(buf)
    t.ok(kbuf.loading_job and kbuf.loading_job ~= job, "following again")
  end)

  it("stops the buffer's jobs when it is wiped", function()
    t.respond("*logs*", { script = "sleep 30" })
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gL")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true")
    local buf = vim.api.nvim_get_current_buf()
    local job = _G.kube_buffers[buf].loading_job
    vim.cmd("bwipeout! " .. buf)
    t.wait_for(function()
      return job:is_closing()
    end, "job to stop")
    t.eq(nil, _G.kube_buffers[buf])
  end)

  it("stops all jobs and port forwards on exit", function()
    t.respond("*logs*", { script = "sleep 30" })
    t.respond("*port-forward*", { script = "sleep 30" })
    t.answer_prompts(function(items)
      return items[1]
    end, "18080")
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "gf")
    local key = utils.portforward_key("ctx-a", "ns1", "pod", "web-1")
    t.wait_for(function()
      return _G.portforwards[key] and _G.portforwards[key][18080]
    end, "port forward")
    local forward_job = _G.portforwards[key][18080].job
    t.restore_stubs()
    t.capture_notify()

    t.press_on("web-1", "gL")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true")
    local logs_job = _G.kube_buffers[vim.api.nvim_get_current_buf()].loading_job

    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    t.wait_for(function()
      return logs_job:is_closing() and forward_job:is_closing()
    end, "jobs to stop")
  end)
end)
