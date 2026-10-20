local t = require("helpers")

require("kube").setup({})
require("kubectl")

local RELEASES = "kube://context/ctx-a/helm-releases"
local WEB = "kube://context/ctx-a/namespaces/ns1/helm-releases/web"
-- Every status, helm 3 and 4 list different ones by default
local LIST = "helm --kube-context ctx-a list --deployed --failed --pending --superseded --uninstalled --uninstalling"

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
local function wait_call(pattern)
  t.wait_for(function()
    return #t.calls_matching(pattern) > 0
  end, "helm call matching " .. pattern)
end

local function wait_lsp()
  t.wait_for(function()
    local client = vim.lsp.get_clients({ bufnr = 0, name = "kube" })[1]
    return client and client.initialized
  end, "the kube language server")
end

---@param title string
local function code_action(title)
  wait_lsp()
  local titles
  vim.lsp.buf.code_action({
    filter = function(action)
      titles = titles or {}
      table.insert(titles, action.title)
      return action.title == title
    end,
    apply = true,
  })
  t.wait_for(function()
    return titles
  end, "code actions")
  t.ok(vim.tbl_contains(titles, title), title .. " not in " .. vim.inspect(titles))
  return titles
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

before_each(function()
  t.reset_kubectl()
  _G.kube.context = nil
  t.respond("*config current-context*", { stdout = "ctx-a\n" })
  t.respond("helm *list * -o json*", { fixture = "helm-list.json" })
  t.respond("helm *history web -o json*", { fixture = "helm-history.json" })
  t.respond("helm *status web*", { stdout = "NAME: web\nSTATUS: deployed\n" })
  t.respond("helm *get values web -o yaml*", { stdout = "replicas: 2\n" })
  t.respond("helm *get manifest web*", { stdout = "---\nkind: ConfigMap\n" })
  t.respond("helm *get notes web*", { stdout = "NOTES:\nThanks\n" })
  t.capture_notify()
end)

after_each(function()
  t.restore_stubs()
  t.clean_buffers()
end)

describe("helm releases", function()
  it("are listed in all namespaces, or in one, of the buffer's context", function()
    open("kube://helm-releases")
    wait_buf_name(RELEASES)
    t.eq({ LIST .. " -o json -A" }, t.calls_matching("^helm"))
    t.eq(2, #t.lines())
    t.ok(t.lines()[1]:match("^ns1%s+web%s+3%s+deployed%s+web%-1%.2%.0%s+1%.2%s+%d+d%s*$"), t.lines()[1])

    t.reset_kubectl()
    t.respond("*config current-context*", { stdout = "ctx-a\n" })
    t.respond("helm *list*", { stdout = "[]" })
    open("kube://ns/ns1/helm-releases")
    t.eq({ LIST .. " -o json -n ns1" }, t.calls_matching("^helm"))
    t.eq("No releases found", t.status())
  end)

  it("report failed releases as diagnostics", function()
    open(RELEASES)
    local diagnostics = vim.diagnostic.get(0)
    t.eq(1, #diagnostics)
    t.eq({ 1, vim.diagnostic.severity.ERROR }, { diagnostics[1].lnum, diagnostics[1].severity })
  end)

  it("are sorted by namespace, then name, as helm sorts by name only", function()
    t.respond("helm *list*", {
      stdout = vim.json.encode({
        { name = "a", namespace = "ns2", revision = "1", status = "deployed" },
        { name = "b", namespace = "ns1", revision = "1", status = "deployed" },
        { name = "c", namespace = "ns1", revision = "1", status = "deployed" },
      }),
    })
    open(RELEASES)
    t.eq(
      { "ns1/b", "ns1/c", "ns2/a" },
      vim.tbl_map(function(line)
        return table.concat(vim.split(line, "%s+", { trimempty = true }), "/", 1, 2)
      end, t.lines())
    )
  end)

  it("ages account for the time zone helm outputs", function()
    local age = require("kube.formatters.helm_releases").age
    t.eq(age("2026-01-01 00:00:00.5 +0000 UTC"), age("2026-01-01 08:00:00.123456 +0800 CST"))
    t.eq(age("2026-01-01T00:00:00Z"), age("2026-01-01T03:00:00.1+03:00"))
    t.eq("", age(nil))
  end)

  it("<CR> opens the manifest, gd the values, - goes back to the list", function()
    open(RELEASES)
    t.press_on("web", "<CR>")
    wait_buf_name(WEB .. "/manifest")
    t.wait_loaded()
    t.eq({ "---", "kind: ConfigMap" }, t.lines())
    t.eq("yaml", vim.bo.filetype)
    t.eq(false, vim.bo.modifiable)

    open(RELEASES)
    t.press_on("web", "gd")
    wait_buf_name(WEB .. "/values")
    t.wait_loaded()
    t.eq({ "replicas: 2" }, t.lines())

    vim.api.nvim_feedkeys("-", "mx", false)
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/helm-releases")
  end)

  it("K shows the status", function()
    open(RELEASES)
    wait_lsp()
    t.press_on("web", "")
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    local result = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 2000)
    t.eq("NAME: web\nSTATUS: deployed", result[next(result)].result.contents.value)
  end)

  it("views are buffers of their own", function()
    open(WEB)
    t.eq({ "NAME: web", "STATUS: deployed" }, t.lines())
    open(WEB .. "/notes")
    t.eq({ "NOTES:", "Thanks" }, t.lines())
    open(WEB .. "/values?all=true")
    open(WEB .. "/manifest?revision=2")
    t.eq({
      "helm --kube-context ctx-a status web -n ns1",
      "helm --kube-context ctx-a get notes web -n ns1",
      "helm --kube-context ctx-a get values web -o yaml --all -n ns1",
      "helm --kube-context ctx-a get manifest web --revision=2 -n ns1",
    }, t.calls_matching("^helm"))
  end)

  it("deleting a line and :w uninstalls the release after confirming", function()
    t.respond("helm * uninstall *", { stdout = 'release "db" uninstalled' })
    local seen = prompts()
    open(RELEASES)
    t.press_on("db", "dd")
    vim.cmd.write()
    wait_call(" uninstall ")
    t.eq({ "Apply the changes (context: ctx-a)?\n  Uninstall helm release ns2/db" }, seen)
    t.eq({ "helm --kube-context ctx-a uninstall db -n ns2" }, t.calls_matching(" uninstall "))
  end)

  it("operations are offered as code actions", function()
    open(RELEASES)
    t.press_on("web", "")
    local titles = code_action("Show history")
    t.eq({
      "Show manifest",
      "Show values",
      "Show all values",
      "Show notes",
      "Show status",
      "Show history",
      "Rollback to the previous revision",
      "Uninstall",
    }, titles)
    wait_buf_name(WEB .. "/history")
    t.wait_loaded()
    t.eq(3, #t.lines())
    t.ok(t.lines()[3]:match("^3%s+%d+d%s+deployed%s+web%-1%.2%.0%s+1%.2%s+Upgrade complete$"), t.lines()[3])
    -- A table, like other lists
    t.eq(false, vim.wo.wrap)
  end)

  it("roll back to the previous revision, or to one of the history", function()
    t.respond("helm *rollback*", { stdout = "Rollback was a success! Happy Helming!" })
    local seen = prompts()
    open(RELEASES)
    t.press_on("web", "")
    code_action("Rollback to the previous revision")
    wait_call("rollback")

    open(WEB .. "/history")
    t.press_on("Install complete", "")
    code_action("Rollback to revision 1")
    t.wait_for(function()
      return #t.calls_matching("rollback") == 2
    end, "second rollback")
    t.eq({
      "Roll back helm release ns1/web (context: ctx-a)?",
      "Roll back helm release ns1/web to revision 1 (context: ctx-a)?",
    }, seen)
    t.eq({
      "helm --kube-context ctx-a rollback web -n ns1",
      "helm --kube-context ctx-a rollback web 1 -n ns1",
    }, t.calls_matching("rollback"))
  end)

  it("<CR> on a revision opens its manifest", function()
    open(WEB .. "/history")
    t.press_on("Install complete", "<CR>")
    wait_buf_name(WEB .. "/manifest?revision=1")
  end)

  it("uninstall several releases at once", function()
    t.respond("helm * uninstall *", { stdout = "uninstalled" })
    prompts()
    open(RELEASES)
    wait_lsp()
    local titles
    vim.lsp.buf.code_action({
      filter = function(action)
        titles = titles or {}
        table.insert(titles, action.title)
        return action.title == "Uninstall 2 releases"
      end,
      apply = true,
      range = { start = { 1, 0 }, ["end"] = { 2, 0 } },
    })
    t.wait_for(function()
      return #t.calls_matching(" uninstall ") == 2
    end, "two uninstalls")
    t.eq({ "Uninstall 2 releases" }, titles)
  end)

  it(":Kube get helm-releases, or helm for short, opens the list", function()
    vim.cmd("Kube get helm-releases namespace=ns1")
    t.wait_loaded()
    wait_buf_name("kube://context/ctx-a/namespaces/ns1/helm-releases")
    vim.cmd("Kube get helm")
    wait_buf_name(RELEASES)
    t.wait_for(function()
      return vim.fn.bufexists("kube://helm") == 0
    end, "the alias buffer to be wiped")
  end)
end)
