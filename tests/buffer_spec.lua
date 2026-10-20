local t = require("helpers")

require("kube").setup({})
local KubeBuffer = require("kube.buffer").KubeBuffer

---Parse a buffer name without loading it.
local function parse(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  local kbuf = KubeBuffer:new(buf)
  return {
    context = kbuf.context,
    namespace = kbuf.namespace,
    resource_kind = kbuf.resource_kind,
    resource_name = kbuf.resource_name,
    subresource_kind = kbuf.subresource_kind,
    params = kbuf.params,
  }
end

describe("KubeBuffer name parsing", function()
  after_each(function()
    t.clean_buffers()
  end)

  it("parses an all-namespaces list", function()
    t.eq({ context = "c", namespace = "all", resource_kind = "deployments" }, parse("kube://context/c/deployments"))
  end)

  it("parses a namespaced subresource with context", function()
    t.eq({
      context = "prod",
      namespace = "ns1",
      resource_kind = "pod",
      resource_name = "web-1",
      subresource_kind = "logs",
      params = { container = "app", follow = true },
    }, parse("kube://context/prod/namespaces/ns1/pod/web-1/logs?container=app&follow=true"))
  end)

  it("decodes the context", function()
    t.eq(
      "arn:aws:eks:us-east-1:1:cluster/prod",
      parse("kube://context/arn%3Aaws%3Aeks%3Aus-east-1%3A1%3Acluster%2Fprod/pods").context
    )
  end)

  it("parses cluster-scoped resources", function()
    t.eq(
      { context = "c", namespace = "all", resource_kind = "node", resource_name = "n1" },
      parse("kube://context/c/node/n1")
    )
  end)

  it("treats namespaces/<name> as the namespace object", function()
    t.eq(
      { context = "c", namespace = "all", resource_kind = "namespaces", resource_name = "ns1" },
      parse("kube://context/c/namespaces/ns1")
    )
  end)

  it("converts flag params to booleans and keeps values with =", function()
    t.eq(
      { selector = "app=web,tier=fe", edit = true, follow = false, output = "yaml" },
      parse("kube://context/c/pods?selector=app=web,tier=fe&edit&follow=false&output=yaml").params
    )
  end)

  it("rejects names without a context or kind", function()
    -- Names without a context are pinned by BufReadCmd before being parsed
    t.ok(not pcall(parse, "kube://pods"))
    t.ok(not pcall(parse, "kube://context/c"))
    t.ok(not pcall(parse, "kube://"))
  end)

  it("returns the same instance for the same buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "kube://context/c/pods")
    t.ok(KubeBuffer:new(buf) == KubeBuffer:new(buf))
  end)
end)

describe("canonical buffer names", function()
  local canonical_name = require("kube.autocmds").canonical_name
  t.respond("*config current-context*", { stdout = "ctx-a\n" })

  it("pins names without a context to the current one", function()
    t.eq("kube://context/ctx-a/pods", canonical_name("kube://pods"))
    t.eq("kube://context/c/pods", canonical_name("kube://context/c/pods"))
    t.eq("kube://portforwards", canonical_name("kube://portforwards"))
  end)

  it("expands ns to namespaces", function()
    t.eq("kube://context/ctx-a/namespaces/prod/pods", canonical_name("kube://ns/prod/pods"))
    t.eq(
      "kube://context/c/namespaces/prod/pods?selector=app",
      canonical_name("kube://context/c/ns/prod/pods?selector=app")
    )
    t.eq("kube://context/ctx-a/namespaces/prod", canonical_name("kube://ns/prod"))
    t.eq("kube://context/ctx-a/namespaces", canonical_name("kube://ns"))
    t.eq("kube://context/ctx-a/namespaces?selector=a", canonical_name("kube://ns?selector=a"))
    t.eq("kube://context/ctx-a/nsx/a", canonical_name("kube://nsx/a"))
    t.eq("kube://context/ctx-a/pods/ns", canonical_name("kube://pods/ns"))
  end)

  it("expands helm to helm-releases", function()
    t.eq("kube://context/ctx-a/helm-releases", canonical_name("kube://helm"))
    t.eq("kube://context/c/namespaces/prod/helm-releases", canonical_name("kube://context/c/ns/prod/helm"))
    t.eq(
      "kube://context/ctx-a/namespaces/prod/helm-releases/web/values?all=true",
      canonical_name("kube://ns/prod/helm/web/values?all=true")
    )
    t.eq("kube://context/ctx-a/helm-releases?a", canonical_name("kube://helm?a"))
    -- A namespace named helm, a pod named helm
    t.eq("kube://context/ctx-a/namespaces/helm/pods", canonical_name("kube://ns/helm/pods"))
    t.eq("kube://context/ctx-a/namespaces/helm", canonical_name("kube://ns/helm"))
    t.eq("kube://context/ctx-a/pods/helm", canonical_name("kube://pods/helm"))
    t.eq("kube://context/ctx-a/helmcharts", canonical_name("kube://helmcharts"))
  end)

  it("lists the resource types without a kind", function()
    t.eq("kube://context/ctx-a/api-resources", canonical_name("kube://"))
    t.eq("kube://context/c/api-resources", canonical_name("kube://context/c"))
    t.eq("kube://context/c/api-resources", canonical_name("kube://context/c/"))
  end)
end)
