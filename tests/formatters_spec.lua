local formatters = require("kube.formatters")
local resources = require("kube.renderers.resources")
local t = require("helpers")

local function rows(kind, fixture, buffer)
  return formatters[kind].format(vim.json.decode(t.fixture(fixture)), buffer)
end

describe("formatters lookup", function()
  it("resolves aliases and falls back to the default", function()
    t.ok(formatters.po == formatters.pods)
    t.ok(formatters["deployments.apps"] == formatters.deploy)
    t.ok(formatters.unknownthings == require("kube.formatters.default"))
  end)
end)

describe("pods formatter", function()
  it("formats ready, restarts and status", function()
    local result = rows("pods", "pods.json")
    t.eq({ "ns1", "web-1", "2/2", "Running", "3", "10.0.0.1", "node-1" }, vim.list_slice(result[1].row, 1, 7))
    t.eq("KubeRunning", result[1].row.highlight)
    t.eq({ "ns1", "web-2", "0/1", "Pending", "0", "", "" }, vim.list_slice(result[2].row, 1, 7))
    t.eq("KubePending", result[2].row.highlight)
  end)

  it("reports diagnostics for pods that are not ready", function()
    local result = rows("pods", "pods.json")
    t.eq({}, result[1].diagnostics)
    t.eq({
      { message = "The pod is not ready: 0/3 nodes are available", severity = vim.diagnostic.severity.WARN },
    }, result[2].diagnostics)
  end)

  it("shows pods being deleted as terminating, like kubectl", function()
    local data = vim.json.decode(t.fixture("pods.json"))
    data.items[1].metadata.deletionTimestamp = "2026-01-01T00:00:00Z"
    data.items[1].status.conditions = { { type = "Ready", status = "False", reason = "PodCompleted" } }
    local row = formatters.pods.format(data)[1]
    t.eq("Terminating", row.row[4])
    t.eq("KubePending", row.row.highlight)
    t.eq(vim.diagnostic.severity.INFO, row.diagnostics[1].severity)
  end)

  it("marks running pods with unready containers as pending", function()
    local data = vim.json.decode(t.fixture("pods.json"))
    data.items[1].status.containerStatuses[1].ready = false
    t.eq("KubePending", formatters.pods.format(data)[1].row.highlight)
  end)
end)

describe("containers formatter", function()
  it("lists containers with status and ports", function()
    local result = rows("containers", "pod-web-1.json")
    t.eq({ "app", "Running", "web:1", "8080/TCP, 9090/TCP", highlight = "KubeRunning" }, result[1].row)
    t.eq({ "sidecar", "Running", "proxy:1", "", highlight = "KubeRunning" }, result[2].row)
    t.eq("app", result[1].item.name)
  end)

  it("reports unknown when there is no status", function()
    t.eq("Unknown", rows("containers", "pod-web-2.json")[1].row[2])
  end)
end)

describe("deployments formatter", function()
  it("formats replica counts", function()
    t.eq({ "ns1", "web", "1/2", "2", "1" }, vim.list_slice(rows("deployments", "deployments.json")[1].row, 1, 5))
  end)
end)

describe("gateways formatter", function()
  it("lists unique sorted hosts", function()
    t.eq("a.example.com,b.example.com", rows("gateways", "gateways.json")[1].row[3])
  end)
end)

describe("default formatter", function()
  it("formats namespace, name and age", function()
    local result = rows("somethings", "deployments.json")
    t.eq({ "ns1", "web" }, vim.list_slice(result[1].row, 1, 2))
  end)
end)

describe("portforward formatter", function()
  after_each(function()
    _G.portforwards = {}
  end)

  it("lists the forwards of the resource in the buffer's context only", function()
    local utils = require("kube.utils")
    _G.portforwards = {
      [utils.portforward_key("a", "ns1", "pod", "web-1")] = {
        [9000] = { container_port = 9090 },
        [8000] = { container_port = 8080 },
      },
      [utils.portforward_key("b", "ns1", "pod", "web-1")] = { [7000] = { container_port = 8080 } },
    }
    local result = rows("portforward", "pod-web-1.json", { context = "a" })
    t.eq({ "ns1", "Pod/web-1", "8000", "8080", "http://localhost:8000" }, result[1].row)
    t.eq({ "9000" }, { result[2].row[3] })
    t.eq(2, #result)
  end)
end)

describe("format_table", function()
  it("aligns columns to the widest value", function()
    local header, formatted, widths = resources.format_table(
      { "NAME", "AGE" },
      { { row = { "a-long-name", "1d" }, item = {} }, { row = { "b", "10d" }, item = {} } }
    )
    t.eq({ 11, 3 }, widths)
    t.eq("NAME         AGE", header.formatted)
    t.eq("a-long-name  1d ", formatted[1].formatted)
    t.eq("b            10d", formatted[2].formatted)
  end)

  it("truncates columns wider than 99", function()
    local long = string.rep("x", 120)
    t.eq(string.rep("x", 96) .. "...", resources.align_row({ long }, { 120 }))
  end)
end)
