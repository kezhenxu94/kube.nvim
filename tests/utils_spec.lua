local t = require("helpers")
local utils = require("kube.utils")

describe("utils.buf_name", function()
  it("builds a current-context, all-namespaces name", function()
    t.eq("kube://deployments", utils.buf_name({ kind = "deployments" }))
    t.eq("kube://deployments", utils.buf_name({ kind = "deployments", namespace = "all" }))
    t.eq("kube://deployments", utils.buf_name({ kind = "deployments", namespace = "ALL" }))
  end)

  it("builds a namespaced name with a context", function()
    t.eq(
      "kube://context/prod/namespaces/ns1/pod/web-1/logs",
      utils.buf_name({ context = "prod", namespace = "ns1", kind = "pod", name = "web-1", subresource = "logs" })
    )
  end)

  it("encodes contexts containing / and :", function()
    t.eq(
      "kube://context/arn%3aaws%3aeks%3aus-east-1%3a1%3acluster%2fprod/pods",
      utils.buf_name({ context = "arn:aws:eks:us-east-1:1:cluster/prod", kind = "pods" })
    )
  end)

  it("ignores a subresource without a name", function()
    t.eq("kube://pods", utils.buf_name({ kind = "pods", subresource = "logs" }))
  end)

  it("sorts params and stringifies values", function()
    t.eq(
      "kube://pod/x?edit=true&output=yaml",
      utils.buf_name({ kind = "pod", name = "x", params = { output = "yaml", edit = true } })
    )
    t.eq("kube://pods", utils.buf_name({ kind = "pods", params = {} }))
  end)
end)

describe("utils.resource_type", function()
  it("uses the bare kind for the core group", function()
    t.eq("pod", utils.resource_type({ apiVersion = "v1", kind = "Pod" }))
  end)

  it("qualifies kinds with their API group", function()
    t.eq("deployment.apps", utils.resource_type({ apiVersion = "apps/v1", kind = "Deployment" }))
    t.eq(
      "gateway.networking.istio.io",
      utils.resource_type({ apiVersion = "networking.istio.io/v1", kind = "Gateway" })
    )
    t.eq(
      "gateway.gateway.networking.k8s.io",
      utils.resource_type({ apiVersion = "gateway.networking.k8s.io/v1", kind = "Gateway" })
    )
  end)

  it("handles a missing apiVersion", function()
    t.eq("pod", utils.resource_type({ kind = "Pod" }))
  end)
end)

describe("utils.portforward_key", function()
  it("separates contexts and resource types", function()
    t.ok(utils.portforward_key("a", "ns", "pod", "x") ~= utils.portforward_key("b", "ns", "pod", "x"))
    t.ok(utils.portforward_key("a", "ns", "pod", "x") ~= utils.portforward_key("a", "ns", "deployment.apps", "x"))
  end)
end)

describe("utils.open", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("does not expand % and # in names", function()
    -- Avoid triggering the plugin, only the name matters here
    vim.api.nvim_create_autocmd("BufReadCmd", { pattern = "kube://*", callback = function() end })
    utils.open({ context = "a/b:c", kind = "pods", params = { selector = "x!=y" } })
    t.eq("kube://context/a%2fb%3ac/pods?selector=x!=y", vim.api.nvim_buf_get_name(0))
  end)
end)

describe("utils.calculate_age", function()
  local function ago(seconds)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - seconds)
  end

  it("formats seconds, minutes, hours and days", function()
    t.eq("5s", utils.calculate_age(ago(5)))
    t.eq("2m5s", utils.calculate_age(ago(125)))
    t.eq("3h", utils.calculate_age(ago(3 * 3600 + 10)))
    t.eq("4d", utils.calculate_age(ago(4 * 86400 + 10)))
  end)
end)

describe("utils.get_winbar", function()
  after_each(function()
    _G.kube_buffers = {}
  end)

  it("works without a number column", function()
    vim.wo.number = false
    vim.wo.signcolumn = "no"
    local buf = vim.api.nvim_get_current_buf()
    _G.kube_buffers = { [buf] = { header_row = { formatted = "NAME  AGE", highlight = "KubeHeader" } } }
    t.eq("%#KubeHeader#NAME  AGE%=%#Comment#", utils.get_winbar(buf))
  end)

  it("pads for the number column", function()
    vim.wo.number = true
    local buf = vim.api.nvim_get_current_buf()
    _G.kube_buffers = { [buf] = { header_row = { formatted = "NAME", highlight = "KubeHeader" } } }
    t.ok(utils.get_winbar(buf):match("^ +%%#KubeHeader#NAME%%=%%#Comment#$"), utils.get_winbar(buf))
  end)
end)
