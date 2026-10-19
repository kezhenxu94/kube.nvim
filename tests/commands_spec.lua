local commands = require("kube.commands")
local t = require("helpers")

require("kube").setup({})
require("kubectl")

describe(":Kube argument parsing", function()
  it("parses get with key=value params whose values contain =", function()
    t.eq(
      { "pods", { namespace = "ns1", selector = "app=web,tier=fe" } },
      commands.command_handlers.get.parse({ "pods", "namespace=ns1", "selector=app=web,tier=fe" })
    )
  end)

  it("parses delete", function()
    t.eq(
      { "pod", "web-1", { namespace = "ns1" } },
      commands.command_handlers.delete.parse({ "pod", "web-1", "namespace=ns1" })
    )
  end)

  it("parses context", function()
    t.eq({ "prod" }, commands.command_handlers.context.parse({ "prod" }))
  end)
end)

describe(":Kube", function()
  before_each(function()
    t.reset_kubectl()
    _G.kube.context = nil
  end)
  after_each(function()
    t.restore_stubs()
  end)

  it("reports unknown subcommands", function()
    local messages = t.capture_notify()
    vim.cmd("Kube nope")
    t.eq({ { msg = "No such command: nope", level = vim.log.levels.ERROR } }, messages)
  end)

  it("context switches the context used for new buffers", function()
    local messages = t.capture_notify()
    vim.cmd("Kube context staging")
    t.eq("staging", require("kubectl").get_current_context())
    t.eq("Switched to context: staging", messages[1].msg)
  end)

  it("context without a name prompts with the current one marked", function()
    t.respond("*config view*", {
      stdout = vim.json.encode({ ["current-context"] = "a", contexts = { { name = "a" }, { name = "b" } } }),
    })
    local shown
    t.answer_prompts(function(items, opts)
      shown = vim.tbl_map(opts.format_item, items)
      return items[2]
    end)
    t.capture_notify()
    vim.cmd("Kube context")
    t.wait_for(function()
      return shown
    end, "context prompt")
    t.eq({ "* a", "  b" }, shown)
    t.eq("b", _G.kube.context)
  end)

  it("delete confirms with the context and deletes in it", function()
    _G.kube.context = "prod"
    t.respond("*delete*", { stdout = "deleted" })
    local prompt
    t.answer_prompts(function(_, opts)
      prompt = opts.prompt
      return "Yes"
    end)
    local messages = t.capture_notify()
    vim.cmd("Kube delete pod web-1 namespace=ns1")
    t.wait_for(function()
      return #messages > 0
    end, "delete notification")
    t.eq("Delete pod: ns1/web-1 (context: prod)?", prompt)
    t.eq({ "--context prod delete pod web-1 -n ns1" }, t.calls())
  end)

  it("delete does nothing when not confirmed", function()
    _G.kube.context = "prod"
    t.answer_prompts(function()
      return "No"
    end)
    vim.cmd("Kube delete pod web-1")
    vim.wait(100)
    t.eq({}, t.calls())
  end)
end)

describe(":Kube completion", function()
  before_each(function()
    t.reset_kubectl()
    _G.kube.context = "completion-ctx"
  end)

  it("completes subcommands", function()
    local items = vim.fn.getcompletion("Kube ", "cmdline")
    table.sort(items)
    t.eq({ "apply", "context", "delete", "diff", "get", "portforwards" }, items)
    t.eq({ "get" }, vim.fn.getcompletion("Kube g", "cmdline"))
  end)

  it("completes resource kinds case-insensitively", function()
    t.respond("*api-resources*", { stdout = "pods\nPodTemplates\ndeployments.apps\n" })
    t.eq({ "pods", "PodTemplates" }, vim.fn.getcompletion("Kube get po", "cmdline"))
    t.eq({ "deployments.apps" }, vim.fn.getcompletion("Kube delete de", "cmdline"))
  end)

  it("completes get params after the kind", function()
    t.eq({ "namespace", "selector" }, vim.fn.getcompletion("Kube get pods ", "cmdline"))
    t.eq({ "selector" }, vim.fn.getcompletion("Kube get pods s", "cmdline"))
  end)

  it("completes delete names in the default namespace", function()
    t.respond("*get pods -o name -n default*", { stdout = "pod/web-1\npod/web-2\npod/db\n" })
    t.eq({ "web-1", "web-2" }, vim.fn.getcompletion("Kube delete pods we", "cmdline"))
    t.eq({ "--context completion-ctx get pods -o name -n default" }, t.calls())
  end)

  it("completes context names", function()
    t.respond("*get-contexts*", { stdout = "prod\nstaging\n" })
    t.eq({ "staging" }, vim.fn.getcompletion("Kube context st", "cmdline"))
  end)
end)
