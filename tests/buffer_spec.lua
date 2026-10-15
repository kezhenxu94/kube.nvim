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
