local constants = require("kube.constants")
local t = require("helpers")
local utils = require("kube.utils")

require("kube").setup({ refresh_interval = 200 })
require("kubectl")

---@param name string
local function open(name)
  vim.cmd.edit(vim.fn.fnameescape(name))
  t.wait_loaded()
end

---@param name string
local function wait_buf_name(name)
  t.wait_for(function()
    return vim.api.nvim_buf_get_name(0) == name
  end, "buffer " .. name .. ", current: " .. vim.api.nvim_buf_get_name(0))
end

---@param pattern string
local function wait_call(pattern, count)
  t.wait_for(function()
    return #t.calls_matching(pattern) >= (count or 1)
  end, "kubectl call matching " .. pattern)
end

local function wait_lsp()
  t.wait_for(function()
    local client = vim.lsp.get_clients({ bufnr = 0, name = "kube" })[1]
    return client and client.initialized
  end, "the kube language server")
end

---Run the code action with `title`, on the cursor line or the given rows (1-indexed).
---@param title string
---@param rows integer[]|nil
local function code_action(title, rows)
  wait_lsp()
  local titles
  vim.lsp.buf.code_action({
    filter = function(action)
      titles = titles or {}
      table.insert(titles, action.title)
      return action.title == title
    end,
    apply = true,
    range = rows and { start = { rows[1], 0 }, ["end"] = { rows[2], 0 } } or nil,
  })
  t.wait_for(function()
    return titles
  end, "code actions")
  t.ok(vim.tbl_contains(titles, title), title .. " not in " .. vim.inspect(titles))
end

---@return string[]
local function prompts()
  local seen = {}
  t.answer_prompts(function(items, opts)
    table.insert(seen, opts.prompt)
    return items[1]
  end)
  return seen
end

local PODS = "kube://context/ctx-a/namespaces/ns1/pods"

before_each(function()
  t.reset_kubectl()
  _G.kube.context = nil
  t.respond("*config current-context*", { stdout = "ctx-a\n" })
  t.respond("*get pods -o json*", { fixture = "pods.json" })
  t.respond("*get deployments -o json*", { fixture = "deployments.json" })
  t.respond("*get deployment.apps web -o yaml*", { fixture = "deployment-web.yaml" })
  t.respond("*get secrets -o json*", { fixture = "secrets.json" })
  t.respond("*get secret -o json db *", { fixture = "secret-db.json" })
  t.respond("*get events -o json*", { fixture = "events.json" })
  t.respond("*get nodes -o json*", { fixture = "nodes.json" })
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

describe("errors", function()
  it("are shown in the buffer and notified", function()
    local messages = t.capture_notify()
    t.respond("*get pods -o json*", { stderr = "Error from server (Forbidden): pods is forbidden", code = 1 })
    open("kube://namespaces/ns1/pods")
    t.eq("✗ Error from server (Forbidden): pods is forbidden", t.status())
    t.eq("Error from server (Forbidden): pods is forbidden", messages[#messages].msg)
  end)

  it("are not notified on background reloads", function()
    open("kube://namespaces/ns1/pods")
    local messages = t.capture_notify()
    t.respond("*get pods -o json*", { stderr = "connection refused", code = 1 })
    _G.kube_buffers[vim.api.nvim_get_current_buf()]:load({ silent = true })
    t.wait_loaded()
    t.eq("✗ connection refused", t.status())
    t.eq({}, messages)
    t.eq(2, #t.lines(), "the last rendered list is kept")
  end)

  it("reloading a closed buffer is a no-op", function()
    open("kube://namespaces/ns1/pods")
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    vim.cmd("bwipeout!")
    kbuf:load()
  end)

  it("lists do not wrap, other views do", function()
    vim.o.wrap = true
    open("kube://namespaces/ns1/pods")
    t.eq(false, vim.wo.wrap)
    open("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    t.eq(true, vim.wo.wrap)
  end)

  it("an empty list says so", function()
    t.respond("*get pods -o json*", { stdout = '{"items":[]}' })
    open("kube://namespaces/ns1/pods")
    t.eq("No resources found", t.status())
  end)
end)

describe("applying YAML", function()
  local EDIT = "kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml"

  before_each(function()
    t.respond("*apply*", { stdout = "deployment.apps/web configured" })
    open(EDIT)
    vim.api.nvim_buf_set_lines(0, 5, 6, false, { "  replicas: 3" })
  end)

  it("shows the diff and applies once confirmed", function()
    t.respond("*diff*", { stdout = "-  replicas: 2\n+  replicas: 3\n", code = 1 })
    local diff_shown
    t.answer_prompts(function(_, opts)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "diff" then
          diff_shown = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        end
      end
      t.eq("Apply deployment.apps/web (context: ctx-a)?", opts.prompt)
      return "Yes"
    end)
    vim.cmd.write()
    wait_call("apply")
    t.eq({ "-  replicas: 2", "+  replicas: 3" }, diff_shown)
    t.eq(1, #t.calls_matching("^%-%-context ctx%-a %-n ns1 diff %-f "))
    t.wait_for(function()
      return not vim.bo.modified
    end, "reload")
    t.eq(1, #vim.api.nvim_tabpage_list_wins(0), "diff window is closed")
  end)

  it("does not apply when declined", function()
    t.respond("*diff*", { stdout = "-a\n+b\n", code = 1 })
    t.answer_prompts(function()
      return "No"
    end)
    vim.cmd.write()
    wait_call("diff")
    vim.wait(100)
    t.eq({}, t.calls_matching("apply"))
    t.eq(true, vim.bo.modified)
  end)

  it(":w! applies without the diff", function()
    vim.cmd("write!")
    wait_call("apply")
    t.eq({}, t.calls_matching("diff"))
  end)

  it("reloads without applying when there is no difference", function()
    t.respond("*diff*", { stdout = "", code = 0 })
    vim.cmd.write()
    t.wait_for(function()
      return not vim.bo.modified
    end, "reload")
    t.eq({}, t.calls_matching("apply"))
  end)

  it("reports diff errors and keeps the edits", function()
    local messages = t.capture_notify()
    t.respond("*diff*", { stderr = "error: invalid object", code = 2 })
    vim.cmd.write()
    t.wait_for(function()
      return #messages > 0
    end)
    t.eq("Failed to diff: error: invalid object", messages[1].msg)
    t.eq(true, vim.bo.modified)
  end)
end)

describe(":Kube apply / diff", function()
  before_each(function()
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "apiVersion: v1", "kind: ConfigMap" })
  end)

  it("apply confirms with the diff in the current context", function()
    t.respond("*diff*", { stdout = "+kind: ConfigMap\n", code = 1 })
    t.respond("*apply*", { stdout = "configmap/x created" })
    local seen = prompts()
    vim.cmd("Kube apply")
    wait_call("apply")
    t.eq({ "Apply buffer (context: ctx-a)?" }, seen)
    t.eq(1, #t.calls_matching("^%-%-context ctx%-a apply %-f .*%.yaml$"))
  end)

  it("Kube! apply skips the confirmation", function()
    t.respond("*apply*", { stdout = "configmap/x created" })
    vim.cmd("Kube! apply")
    wait_call("apply")
    t.eq({}, t.calls_matching("diff"))
  end)

  it("diff shows the differences", function()
    t.respond("*diff*", { stdout = "+kind: ConfigMap\n", code = 1 })
    vim.cmd("Kube diff")
    t.wait_for(function()
      return #vim.api.nvim_tabpage_list_wins(0) == 2
    end, "diff window")
    t.eq({}, t.calls_matching("apply"))
  end)
end)

describe("secrets", function()
  local DATA = "kube://context/ctx-a/namespaces/ns1/secret/db/data"

  it("<CR> shows the decoded data", function()
    open("kube://namespaces/ns1/secrets")
    t.press_on("db", "<CR>")
    wait_buf_name(DATA)
    t.wait_loaded()
    local lines = t.lines()
    t.eq({
      'cert: !!binary "/wAB"',
      'password: "p@ss\\"word\\nline2"',
      'username: "admin"',
    }, vim.list_slice(lines, #require("kube.secret").HEADER + 1))
    t.eq(true, vim.bo.modifiable)
  end)

  it("saving patches added, changed and removed keys", function()
    t.respond("*patch*", { stdout = "secret/db patched" })
    open(DATA)
    local seen = prompts()
    local header = #require("kube.secret").HEADER
    vim.api.nvim_buf_set_lines(0, header, -1, false, {
      'password: "p@ss\\"word\\nline2"',
      'username: "root"',
      'token: "abc"',
    })
    vim.cmd.write()
    wait_call("patch")

    t.eq({ "Update secret ns1/db (context: ctx-a): added token; changed username; removed cert?" }, seen)
    local patch = vim.json.decode(t.calls_matching("patch")[1]:match("%-p (%b{})"))
    t.eq({ data = { token = vim.base64.encode("abc"), username = vim.base64.encode("root"), cert = vim.NIL } }, patch)
    t.eq(1, #t.calls_matching("^%-%-context ctx%-a patch secret db %-%-type=merge %-p .* %-n ns1$"))
  end)

  it("rejects invalid lines", function()
    local messages = t.capture_notify()
    open(DATA)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "broken line" })
    vim.cmd.write()
    t.eq('Invalid secret data, line 7: expected `key: "value"`', messages[#messages].msg)
    t.eq({}, t.calls_matching("patch"))
  end)

  it("round-trips values exactly", function()
    local secret = require("kube.secret")
    local data = vim.json.decode(t.fixture("secret-db.json")).data
    t.eq(data, secret.from_lines(secret.to_lines(data)))
  end)
end)

describe("events", function()
  it("lists the most recent first with warnings as diagnostics", function()
    open("kube://namespaces/ns1/events")
    t.ok(t.lines()[1]:match("Warning%s+BackOff%s+deployment/web%s+Back%-off restarting failed container"), t.lines()[1])
    t.ok(t.lines()[2]:match("Normal%s+Pulled%s+pod/web%-1"), t.lines()[2])
    local diagnostics = vim.diagnostic.get(0)
    t.eq(1, #diagnostics)
    t.eq(0, diagnostics[1].lnum)
  end)

  it("of a workload include the pods it selects", function()
    t.respond("*get deployment.apps -o json web *", { fixture = "deployment-web.json" })
    t.respond("*get pods,replicasets -o json*", { fixture = "pods.json" })
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "")
    code_action("Show events")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/events?for=deployment.apps/web")
    t.wait_for(function()
      return #t.lines() == 2
    end, "events of the deployment and its pods")
    t.ok(t.lines()[1]:find("deployment/web", 1, true), t.lines()[1])
    t.ok(t.lines()[2]:find("pod/web-1", 1, true), t.lines()[2])
    t.eq(
      { "--context ctx-a get pods,replicasets -o json -n ns1 --selector=app=web,tier=frontend" },
      t.calls_matching("pods,replicasets")
    )
  end)

  it("of a resource without a selector are its own", function()
    t.respond("*get configmap -o json cfg *", {
      stdout = vim.json.encode({
        apiVersion = "v1",
        kind = "ConfigMap",
        metadata = { name = "cfg", namespace = "ns1" },
      }),
    })
    open("kube://context/ctx-a/namespaces/ns1/events?for=configmap/cfg")
    t.wait_for(function()
      return t.status() == "No events: Kubernetes keeps events for 1 hour by default"
    end, "the empty status")
    t.eq({}, t.calls_matching("pods,replicasets"))
  end)

  it("explain why there are none", function()
    t.respond("*get events -o json*", { stdout = '{"items":[]}' })
    open("kube://namespaces/ns1/events")
    t.eq("No events: Kubernetes keeps events for 1 hour by default", t.status())
  end)

  it("<C-]> on the object goes to it", function()
    open("kube://namespaces/ns1/events")
    t.press_on("deployment/web", "<C-]>")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
  end)

  it("are shown for the resource under the cursor", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "")
    code_action("Show events")
    wait_buf_name(PODS:gsub("pods$", "events") .. "?field-selector=involvedObject.kind=Pod,involvedObject.name=web-1")
    wait_call("get events")
    t.eq(
      1,
      #t.calls_matching(
        "get events %-o json %-n ns1 %-%-field%-selector=involvedObject.kind=Pod,involvedObject.name=web%-1$"
      )
    )
  end)
end)

describe("operations", function()
  it("scale", function()
    t.respond("*scale*", { stdout = "deployment.apps/web scaled" })
    t.answer_prompts(nil, "3")
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "")
    code_action("Scale…")
    wait_call("scale")
    t.eq({ "--context ctx-a scale deployment.apps/web --replicas=3 -n ns1" }, t.calls_matching("scale"))
    wait_call("get deployments", 2)
  end)

  it("restart and undo confirm with the context", function()
    t.respond("*rollout*", { stdout = "ok" })
    local seen = prompts()
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "")
    code_action("Restart")
    wait_call("rollout restart")
    code_action("Undo rollout")
    wait_call("rollout undo")
    t.eq({
      "Restart deployment.apps/web (context: ctx-a)?",
      "Undo the rollout of deployment.apps/web (context: ctx-a)?",
    }, seen)
    t.eq({
      "--context ctx-a rollout restart deployment.apps/web -n ns1",
      "--context ctx-a rollout undo deployment.apps/web -n ns1",
    }, t.calls_matching("rollout"))
  end)

  it("rollout history", function()
    t.respond("*rollout history*", { stdout = "REVISION  CHANGE-CAUSE\n1         <none>\n" })
    open("kube://namespaces/ns1/deployments")
    t.press_on("web", "")
    code_action("Rollout history")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web/history")
    t.wait_loaded()
    t.eq({ "REVISION  CHANGE-CAUSE", "1         <none>" }, t.lines())
  end)

  it("logs with options", function()
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "")
    code_action("Show logs of the previous instance")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?previous=true")
    wait_call("logs")
    t.eq({ "--context ctx-a logs pod/web-1 -n ns1 --tail=1000 --previous" }, t.calls_matching("logs"))
  end)

  it("trigger a cron job now", function()
    t.respond("*get cronjobs -o json*", {
      stdout = vim.json.encode({
        items = {
          {
            apiVersion = "batch/v1",
            kind = "CronJob",
            metadata = { name = "report", namespace = "ns1", creationTimestamp = "2026-01-01T00:00:00Z" },
            spec = { schedule = "0 * * * *" },
            status = {},
          },
        },
      }),
    })
    t.respond("*create job*", { stdout = "job.batch/report-manual-1 created" })
    local seen = prompts()
    open("kube://namespaces/ns1/cronjobs")
    t.press_on("report", "")
    code_action("Trigger now")
    wait_call("create job")
    t.eq({ "Trigger cronjob.batch/report (context: ctx-a)?" }, seen)
    local call = t.calls_matching("create job")[1]
    t.ok(call:match("^%-%-context ctx%-a create job report%-manual%-%d+ %-%-from=cronjob/report %-n ns1$"), call)
  end)

  it("debug a pod in an ephemeral container", function()
    local cmd
    t.stub(vim.fn, "jobstart", function(c)
      cmd = c
      return 1
    end)
    t.answer_prompts(function(items)
      return items[2]
    end, "nicolaka/netshoot")
    open("kube://namespaces/ns1/pods")
    t.press_on("web-1", "")
    code_action("Debug (ephemeral container)")
    t.wait_for(function()
      return cmd
    end, "kubectl debug")
    vim.cmd.stopinsert()
    t.eq({
      "kubectl",
      "--context",
      "ctx-a",
      "debug",
      "-it",
      "pod/web-1",
      "--image=nicolaka/netshoot",
      "-n",
      "ns1",
      "--target=sidecar",
      "--",
      "sh",
    }, cmd)
    t.eq(
      "kube://context/ctx-a/namespaces/ns1/pod/web-1/debug?image=nicolaka/netshoot&target=sidecar",
      vim.api.nvim_buf_get_name(0)
    )
  end)

  it("on a range apply to all selected resources", function()
    t.respond("*delete*", { stdout = "deleted" })
    local seen = prompts()
    open("kube://namespaces/ns1/pods")
    code_action("Delete 2 resources", { 1, 2 })
    wait_call("delete", 2)
    t.eq({ "Delete pod/web-1, pod/web-2 (context: ctx-a)?" }, seen)
  end)

  it("on nodes", function()
    t.respond("*cordon*", { stdout = "cordoned" })
    t.respond("*drain*", { stdout = "drained" })
    local seen = prompts()
    open("kube://nodes")
    code_action("Cordon 2 resources", { 1, 2 })
    wait_call("cordon", 2)
    t.eq({}, seen, "cordon is not confirmed")
    t.press_on("node-2", "")
    code_action("Drain")
    wait_call("drain")
    t.eq({ "Drain node/node-2 (context: ctx-a)?" }, seen)
    t.eq({ "--context ctx-a drain node-2 --ignore-daemonsets --delete-emptydir-data" }, t.calls_matching("drain"))
  end)

  it("are offered by kind", function()
    open("kube://namespaces/ns1/pods")
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    local operations = require("kube.operations")
    local function titles(items)
      return vim.tbl_map(function(operation)
        return operation.title
      end, operations.for_items(kbuf, items))
    end
    local pod = vim.json.decode(t.fixture("pod-web-1.json"))
    local deployment = vim.json.decode(t.fixture("deployments.json")).items[1]
    t.ok(vim.tbl_contains(titles({ pod }), "Exec"))
    t.ok(not vim.tbl_contains(titles({ pod }), "Scale…"))
    t.ok(vim.tbl_contains(titles({ deployment }), "Scale…"))
    t.eq({ "Delete 2 resources" }, titles({ pod, deployment }), "mixed kinds only share delete")
  end)
end)

describe("resource types", function()
  it("offer listing them, in all namespaces, and their events", function()
    t.respond("*api-resources*", { fixture = "api-resources.txt" })
    t.respond("*get events*", { stdout = '{"items":[]}' })
    t.respond("*get deployments.apps*", { fixture = "deployments.json" })
    open("kube://ns/ns1/api-resources")
    vim.fn.search("deployments")
    code_action("Show events")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/events?field-selector=involvedObject.kind=Deployment")
    vim.cmd("normal! \15")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/api-resources")
    vim.fn.search("deployments")
    code_action("List in all namespaces")
    wait_buf_name("kube://context/ctx-a/deployments.apps")
  end)
end)

describe("global port forwards", function()
  it("lists forwards of all contexts, deleting a line stops it", function()
    t.respond("*port-forward*", { script = "sleep 30" })
    local function forward(name, local_port)
      local asked = false
      t.answer_prompts(function(items)
        if asked then
          return nil
        end
        asked = true
        return items[1]
      end, tostring(local_port))
      open(name)
      t.press_on("web-1", "gf")
    end
    forward("kube://context/ctx-a/namespaces/ns1/pods", 18080)
    forward("kube://context/ctx-b/namespaces/ns1/pods", 28080)
    t.restore_stubs()
    t.capture_notify()

    vim.cmd("Kube portforwards")
    wait_buf_name("kube://portforwards")
    t.eq(2, #t.lines())
    t.ok(t.lines()[1]:match("^ctx%-a%s+ns1%s+pod/web%-1%s+18080%s+8080%s+http://localhost:18080"), t.lines()[1])
    t.ok(t.lines()[2]:match("^ctx%-b"), t.lines()[2])

    local job = _G.portforwards[utils.portforward_key("ctx-b", "ns1", "pod", "web-1")][28080].job
    t.answer_prompts(function()
      return "Yes"
    end)
    t.press_on("ctx-b", "dd")
    vim.cmd.write()
    t.wait_for(function()
      return job:is_closing() and #t.lines() == 1
    end, "forward to stop")
    t.ok(_G.portforwards[utils.portforward_key("ctx-a", "ns1", "pod", "web-1")][18080], "the other forward is kept")
  end)

  it("offer stopping them and going to the forwarded resource", function()
    t.respond("*port-forward*", { script = "sleep 30" })
    t.respond("*get pod web-1 -o yaml*", { stdout = "kind: Pod" })
    t.answer_prompts(function(items)
      return items[1]
    end, "18080")
    open("kube://context/ctx-a/namespaces/ns1/pods")
    t.press_on("web-1", "gf")
    local key = utils.portforward_key("ctx-a", "ns1", "pod", "web-1")
    t.wait_for(function()
      return _G.portforwards[key] and _G.portforwards[key][18080]
    end, "port forward")
    local job = _G.portforwards[key][18080].job

    vim.cmd.edit("kube://portforwards")
    code_action("Go to pod/web-1")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/pod/web-1?output=yaml")
    vim.cmd("normal! \15")
    wait_buf_name("kube://portforwards")

    t.answer_prompts(function()
      return "Yes"
    end)
    code_action("Stop")
    t.wait_for(function()
      return job:is_closing()
    end, "forward to stop")
    t.eq(nil, _G.portforwards[key][18080])
  end)
end)

describe("watch", function()
  it("gw toggles periodic reloads, paused while the buffer is modified", function()
    open("kube://namespaces/ns1/pods")
    t.eq(1, #t.calls_matching("get pods"))

    vim.api.nvim_feedkeys("gw", "mx", false)
    t.ok(vim.wo.winbar:find("⟳ 0.2s", 1, true), vim.wo.winbar)
    wait_call("get pods", 3)

    vim.cmd("normal! dd")
    local paused = #t.calls_matching("get pods")
    vim.wait(500)
    t.eq(paused, #t.calls_matching("get pods"), "no reload while modified")
    vim.cmd("normal! u")

    vim.api.nvim_feedkeys("gw", "mx", false)
    t.ok(not vim.wo.winbar:find("⟳", 1, true), vim.wo.winbar)
    vim.wait(300)
    local stopped = #t.calls_matching("get pods")
    vim.wait(500)
    t.eq(stopped, #t.calls_matching("get pods"), "no reload once toggled off")
  end)

  it("is only for lists", function()
    local messages = t.capture_notify()
    open("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    vim.api.nvim_feedkeys("gw", "mx", false)
    t.eq("Only resource lists can be watched", messages[#messages].msg)
  end)
end)

describe("language server", function()
  it("attaches to kube buffers", function()
    open("kube://namespaces/ns1/pods")
    wait_lsp()
    t.eq(
      { "kube" },
      vim.tbl_map(function(client)
        return client.name
      end, vim.lsp.get_clients({ bufnr = 0 }))
    )
  end)

  it("stays attached, with the keymaps, after :e reloads the buffer", function()
    open("kube://namespaces/ns1/pods")
    wait_lsp()
    vim.cmd.edit()
    t.wait_loaded()
    wait_lsp()
    t.ok(vim.fn.maparg("g?", "n", false, true).buffer == 1, "buffer keymaps")
    t.eq(1, #vim.lsp.get_clients({ name = "kube" }), "the same server")
  end)

  it("reports hover progress while kubectl describes", function()
    local reported = {}
    local id = vim.api.nvim_create_autocmd("LspProgress", {
      callback = function(ev)
        local value = ev.data.params.value
        table.insert(reported, { kind = value.kind, title = value.title, message = value.message })
      end,
    })
    t.respond("*describe*", { script = "sleep 0.3; echo 'Name: web-1'" })
    open("kube://namespaces/ns1/pods")
    wait_lsp()
    t.press_on("web-1", "K")
    t.wait_for(function()
      return #reported == 2
    end, "progress begin and end")
    t.eq({ kind = "begin", title = "Describing pod/web-1" }, reported[1])
    t.eq({ "end", nil }, { reported[2].kind, reported[2].message })

    reported = {}
    t.respond("*describe*", { stderr = "forbidden", code = 1 })
    t.press_on("web-2", "K")
    t.wait_for(function()
      return #reported == 2
    end, "progress begin and end")
    t.eq({ "end", "Failed" }, { reported[2].kind, reported[2].message })
    vim.api.nvim_del_autocmd(id)
  end)

  it("lists the resources as document symbols", function()
    open("kube://namespaces/ns1/pods")
    wait_lsp()
    local result = vim.lsp.buf_request_sync(0, "textDocument/documentSymbol", {
      textDocument = vim.lsp.util.make_text_document_params(0),
    }, 2000)
    local symbols = vim.tbl_map(function(symbol)
      return { symbol.name, symbol.detail, symbol.range.start.line }
    end, result[next(result)].result)
    t.eq({ { "web-1", "ns1", 0 }, { "web-2", "ns1", 1 } }, symbols)
  end)

  it("definition is what the cell under the cursor refers to", function()
    open("kube://pods")
    wait_lsp()
    t.press_on("ns1", "")
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    local result = vim.lsp.buf_request_sync(0, "textDocument/definition", params, 2000)
    t.eq(PODS, result[next(result)].result.uri)
  end)

  it("selection ranges are the cell, the row, then the list", function()
    open(PODS)
    wait_lsp()
    t.press_on("web-1", "")
    local line = vim.api.nvim_get_current_line()
    local first = line:find("web-1", 1, true) - 1
    local result = vim.lsp.buf_request_sync(0, "textDocument/selectionRange", {
      textDocument = vim.lsp.util.make_text_document_params(0),
      positions = { { line = 0, character = first + 2 }, { line = 0, character = first + 5 } },
    }, 2000)
    local cell, between = unpack(result[next(result)].result)
    t.eq({ start = { line = 0, character = first }, ["end"] = { line = 0, character = first + 5 } }, cell.range)
    t.eq({ start = { line = 0, character = 0 }, ["end"] = { line = 0, character = #line } }, cell.parent.range)
    t.eq(1, cell.parent.parent.range["end"].line)
    t.eq(cell.parent.range, between.range, "the row between cells")
  end)

  it("gD goes to the owner, the controller first", function()
    local pods = vim.json.decode(t.fixture("pods.json"))
    pods.items[1].metadata.ownerReferences = {
      { apiVersion = "v1", kind = "Node", name = "node-1" },
      { apiVersion = "apps/v1", kind = "ReplicaSet", name = "web-abc", controller = true },
    }
    t.respond("*get pods -o json*", { stdout = vim.json.encode(pods) })
    open(PODS)
    wait_lsp()
    t.press_on("web-1", "gD")
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/replicaset.apps/web-abc?output=yaml")
  end)

  it("declaration in a YAML buffer is the owner of its resource", function()
    local deployment = vim.json.decode(t.fixture("deployment-web.json"))
    deployment.metadata.ownerReferences = { { apiVersion = "example.com/v1", kind = "App", name = "web" } }
    t.respond("*get deployment.apps -o json web *", { stdout = vim.json.encode(deployment) })
    open("kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml")
    wait_lsp()
    vim.lsp.buf.declaration()
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/app.example.com/web?output=yaml")
  end)

  ---@return lsp.Location[]
  local function references()
    local params = vim.lsp.util.make_position_params(0, "utf-8")
    params.context = { includeDeclaration = false }
    local result = vim.lsp.buf_request_sync(0, "textDocument/references", params, 2000)
    return result[next(result)].result
  end

  it("references are the pods using the resource, as rows of a list", function()
    local pods = vim.json.decode(t.fixture("pods.json"))
    pods.items[2].spec.containers[1].envFrom = { { secretRef = { name = "db" } } }
    t.respond("*get pods -o json*", { stdout = vim.json.encode(pods) })
    open("kube://context/ctx-a/namespaces/ns1/secrets")
    wait_lsp()
    t.press_on("db", "")
    local uri = "kube://context/ctx-a/namespaces/ns1/pods?using=secret/db"
    t.eq(
      { { uri = uri, range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } } } },
      references()
    )
    local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(uri), 0, -1, false)
    t.eq(1, #lines)
    t.ok(lines[1]:find("web-2", 1, true), lines[1])

    -- Again: the list is reloaded
    t.eq(1, #references())
    t.eq(2, #t.calls_matching("get pods"))
  end)

  it("references of a node are the pods of all namespaces on it", function()
    open("kube://context/ctx-a/nodes")
    wait_lsp()
    t.press_on("node-1", "")
    local locations = references()
    t.eq(1, #locations)
    t.eq("kube://context/ctx-a/pods?using=node/node-1", locations[1].uri)
    t.eq(1, #t.calls_matching("get pods %-o json %-%-all%-namespaces %-%-field%-selector=spec.nodeName=node%-1"))
  end)

  local DEPLOYMENT_YAML = "kube://context/ctx-a/namespaces/ns1/deployment.apps/web?output=yaml"

  local function respond_deployment_yaml()
    t.respond("*get deployment.apps web -o yaml*", {
      stdout = table.concat({
        "apiVersion: apps/v1",
        "kind: Deployment",
        "metadata:",
        "  name: web",
        "spec:",
        "  template:",
        "    spec:",
        "      containers:",
        "      - env:",
        "        - name: MODE",
        "          value: x",
        "        image: web:1",
        "        name: app",
        "      - image: proxy:1",
        "        name: sidecar",
        "      initContainers:",
        "      - image: busybox",
        "        name: init",
      }, "\n"),
    })
  end

  it("code lenses run operations on the containers of a YAML", function()
    respond_deployment_yaml()
    open(DEPLOYMENT_YAML)
    wait_lsp()
    local result = vim.lsp.buf_request_sync(0, "textDocument/codeLens", {
      textDocument = vim.lsp.util.make_text_document_params(0),
    }, 2000)
    local lenses = result[next(result)].result
    t.eq(
      {
        "8 app Show logs",
        "8 app Follow logs",
        "8 app Exec",
        "13 sidecar Show logs",
        "13 sidecar Follow logs",
        "13 sidecar Exec",
      },
      vim.tbl_map(function(lens)
        return string.format("%d %s %s", lens.range.start.line, lens.command.arguments[2], lens.command.title)
      end, lenses)
    )

    vim.lsp.get_clients({ bufnr = 0, name = "kube" })[1]:exec_cmd(lenses[5].command)
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/deployment.apps/web/logs?container=sidecar&follow=true")
  end)

  if vim.fn.has("nvim-0.12") == 1 then
    it("code lenses are shown once the YAML is loaded", function()
      respond_deployment_yaml()
      vim.lsp.codelens.enable(true)
      open(DEPLOYMENT_YAML)
      t.wait_for(function()
        return #vim.lsp.codelens.get({ bufnr = 0 }) == 6
      end, "the code lenses")
      vim.lsp.codelens.enable(false)
    end)

    it("an / in select the cell, the row and back", function()
      open(PODS)
      wait_lsp()
      t.press_on("web-1", "lvany")
      t.eq("web-1", vim.fn.getreg('"'))
      t.press_on("web-1", "lvanany")
      t.eq(vim.api.nvim_get_current_line(), vim.fn.getreg('"'))
      t.press_on("web-1", "lvananiny")
      t.eq("web-1", vim.fn.getreg('"'))
    end)
  end
end)

---@param ns integer
---@return vim.api.keyset.get_extmark_item[]
local function extmarks(ns)
  return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

---Put the cursor on the `column` cell of the row of `name` and press `keys`.
---@param name string
---@param column string
---@param keys string
local function edit_cell(name, column, keys)
  local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
  for id, cell in pairs(kbuf.mark_columns) do
    local item_name = cell.item and (cell.item.metadata and cell.item.metadata.name or cell.item.name)
    if cell.column == column and item_name == name then
      local mark = vim.api.nvim_buf_get_extmark_by_id(0, constants.KUBE_COLUMN_NAMESPACE, id, {})
      vim.api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
      vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
      return
    end
  end
  error(string.format("no %s cell for %s", column, name))
end

describe("lists", function()
  it("aligns the header with the sign column of the diagnostics", function()
    open(PODS)
    t.ok(#vim.diagnostic.get(0) > 0, "an unhealthy pod")
    local textoff = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
    t.ok(textoff > 0, "a sign column")
    t.eq(string.rep(" ", textoff) .. "%#", vim.wo.winbar:sub(1, textoff + 2))
  end)

  it("show deleted rows until they are written or restored", function()
    open(PODS)
    -- Like typing, so each delete can be undone
    vim.cmd("let &undolevels = &undolevels")
    t.press_on("web-1", "dd")
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    local marks = extmarks(constants.KUBE_PENDING_NAMESPACE)
    t.eq(1, #marks)
    t.eq(0, marks[1][2])
    t.ok(marks[1][4].virt_lines_above)
    t.ok(marks[1][4].virt_lines[1][1][1]:match("^ns1%s+web%-1%s+2/2"), vim.inspect(marks[1][4].virt_lines))
    t.eq("KubeDeleted", marks[1][4].virt_lines[1][1][2])
    t.eq(1, vim.fn.winsaveview().topfill, "scrolled to show the line above the first one")

    vim.cmd("let &undolevels = &undolevels")
    t.press_on("web-2", "dd")
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    marks = extmarks(constants.KUBE_PENDING_NAMESPACE)
    t.eq(1, #marks, "below the last line")
    t.eq(2, #marks[1][4].virt_lines)
    t.ok(not marks[1][4].virt_lines_above)

    vim.cmd("silent normal! uu")
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    t.eq({}, extmarks(constants.KUBE_PENDING_NAMESPACE))
  end)

  it("highlight cells rather than rows", function()
    open(PODS)
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    local highlighted = {}
    for _, mark in ipairs(extmarks(constants.KUBE_COLUMN_NAMESPACE)) do
      if mark[4].hl_group then
        local cell = kbuf.mark_columns[mark[1]]
        table.insert(highlighted, string.format("%s %s %s", cell.item.metadata.name, cell.column, mark[4].hl_group))
      end
    end
    table.sort(highlighted)
    t.eq({
      "web-1 RESTARTS KubePending",
      "web-1 STATUS KubeRunning",
      "web-2 STATUS KubePending",
    }, highlighted)
  end)

  it("highlight the cells of editable columns", function()
    open("kube://namespaces/ns1/deployments")
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    local editable = {}
    for _, mark in ipairs(extmarks(constants.KUBE_COLUMN_NAMESPACE)) do
      if mark[4].hl_group == "KubeEditable" then
        table.insert(editable, kbuf.mark_columns[mark[1]].column)
      end
    end
    t.ok(#editable > 0)
    t.eq({ "DESIRED" }, vim.fn.uniq(vim.fn.sort(editable)))
  end)

  it("flash the rows a watched reload changed", function()
    open(PODS)
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]

    -- Only the order changed
    t.respond("*get pods -o json*", { fixture = "pods-reversed.json" })
    kbuf:load({ silent = true })
    t.wait_loaded()
    t.eq({}, extmarks(constants.KUBE_CHANGED_NAMESPACE))

    local data = vim.json.decode(t.fixture("pods.json"))
    data.items[2].status.phase = "Failed"
    t.respond("*get pods -o json*", { stdout = vim.json.encode(data) })
    kbuf:load({ silent = true })
    t.wait_loaded()
    local marks = extmarks(constants.KUBE_CHANGED_NAMESPACE)
    t.eq(1, #marks)
    t.ok(t.lines()[marks[1][2] + 1]:match("web%-2"), t.lines()[marks[1][2] + 1])
    t.wait_for(function()
      return #extmarks(constants.KUBE_CHANGED_NAMESPACE) == 0
    end, "the flash to end")

    -- A reload asked for does not flash
    data.items[2].status.phase = "Pending"
    t.respond("*get pods -o json*", { stdout = vim.json.encode(data) })
    kbuf:load()
    t.wait_loaded()
    t.eq({}, extmarks(constants.KUBE_CHANGED_NAMESPACE))
  end)
end)

describe("editing cells", function()
  it("scales after confirming the edited DESIRED", function()
    t.respond("*scale*", { stdout = "deployment.apps/web scaled" })
    local seen = prompts()
    open("kube://namespaces/ns1/deployments")
    edit_cell("web", "DESIRED", "ciw5<Esc>")
    vim.cmd.write()
    wait_call("scale")
    t.eq({ "Apply the changes (context: ctx-a)?\n  Scale deployment.apps/web: 3 → 5" }, seen)
    t.eq({ "--context ctx-a scale deployment.apps/web --replicas=5 -n ns1" }, t.calls_matching("scale"))
    wait_call("get deployments", 2)
  end)

  it("applies edits and deletes together, :w! without confirming", function()
    t.respond("*scale*", { stdout = "scaled" })
    t.respond("*delete*", { stdout = "deleted" })
    local data = vim.json.decode(t.fixture("deployments.json"))
    local api = vim.deepcopy(data.items[1])
    api.metadata.name = "api"
    table.insert(data.items, api)
    t.respond("*get deployments -o json*", { stdout = vim.json.encode(data) })
    local seen = prompts()
    open("kube://namespaces/ns1/deployments")
    edit_cell("web", "DESIRED", "ciw0<Esc>")
    t.press_on("api", "dd")
    vim.cmd("write!")
    wait_call("scale")
    wait_call("delete")
    t.eq({}, seen)
    t.eq({ "--context ctx-a delete deployment.apps api -n ns1" }, t.calls_matching("delete"))
  end)

  it("rejects invalid values and keeps the edits", function()
    local messages = t.capture_notify()
    open("kube://namespaces/ns1/deployments")
    edit_cell("web", "DESIRED", "ciw-1<Esc>")
    vim.cmd.write()
    t.eq("Invalid number of replicas for deployment.apps/web: -1", messages[#messages].msg)
    t.eq(vim.log.levels.ERROR, messages[#messages].level)
    t.eq({}, t.calls_matching("scale"))
    t.ok(vim.bo.modified)
  end)

  it("rejects edits of other columns and keeps the edits", function()
    local messages = t.capture_notify()
    open("kube://namespaces/ns1/pods")
    edit_cell("web-1", "NAMESPACE", "ciwns2<Esc>")
    vim.cmd.write()
    t.eq("NAMESPACE of pod/web-1 is not editable", messages[#messages].msg)
    t.eq(vim.log.levels.ERROR, messages[#messages].level)
    t.ok(vim.bo.modified)
  end)

  it("sets the image of a container", function()
    t.respond("*get pod -o json web-1 *", { fixture = "pod-web-1.json" })
    t.respond("*set image*", { stdout = "pod/web-1 image updated" })
    open("kube://namespaces/ns1/pod/web-1/containers")
    edit_cell("app", "IMAGE", vim.fn.has("nvim-0.12") == 1 and "canweb:2<Esc>" or "cWweb:2<Esc>")
    vim.cmd("write!")
    wait_call("set image")
    t.eq({ "--context ctx-a set image pod/web-1 app=web:2 -n ns1" }, t.calls_matching("set image"))
  end)
end)

describe("metrics", function()
  it("adds CPU and MEMORY columns from kubectl top", function()
    t.respond("*top pods*", { stdout = "web-1   12m   34Mi\n" })
    open(PODS)
    t.eq({ "--context ctx-a top pods --no-headers -n ns1" }, t.calls_matching("top"))
    local kbuf = _G.kube_buffers[vim.api.nvim_get_current_buf()]
    t.ok(kbuf.header_row.formatted:match("NODE%s+CPU%s+MEMORY%s+AGE"), kbuf.header_row.formatted)
    t.ok(t.lines()[1]:match("^ns1%s+web%-1 .* node%-1%s+12m%s+34Mi%s+%d"), t.lines()[1])
    t.ok(t.lines()[2]:match("Pending%s+0%s+%d+[smhd]"), t.lines()[2])
  end)

  it("are not asked again when the cluster has no metrics API", function()
    t.respond("*top nodes*", { stderr = "error: Metrics API not available", code = 1 })
    open("kube://context/ctx-c/nodes")
    t.ok(t.lines()[1]:match("^node%-1%s+Ready"), t.lines()[1])
    vim.cmd("normal R")
    t.wait_loaded()
    t.eq(2, #t.calls_matching("get nodes"))
    t.eq(1, #t.calls_matching("top nodes"))
  end)
end)

describe("following logs", function()
  it("keeps the cursor at the end and drops the oldest lines", function()
    t.stub(require("kube.config").values.logs, "max_lines", 3)
    t.respond("*logs*", { script = "printf 'a\\nb\\n'; sleep 0.2; printf 'c\\nd\\ne\\n'; sleep 30" })
    vim.cmd.edit("kube://context/ctx-a/namespaces/ns1/pod/web-1/logs?follow=true")
    t.wait_for(function()
      return t.lines()[1] == "c"
    end, "the oldest lines to be dropped")
    t.eq({ "c", "d", "e", "" }, t.lines())
    t.eq(4, vim.api.nvim_win_get_cursor(0)[1])
  end)
end)
