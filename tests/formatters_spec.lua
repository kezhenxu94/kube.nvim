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
    t.eq({ STATUS = "KubeRunning", RESTARTS = "KubePending" }, result[1].highlights)
    t.eq({ "ns1", "web-2", "0/1", "Pending", "0", "", "" }, vim.list_slice(result[2].row, 1, 7))
    t.eq({ STATUS = "KubePending" }, result[2].highlights)
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
    t.eq("KubePending", row.highlights.STATUS)
    t.eq(vim.diagnostic.severity.INFO, row.diagnostics[1].severity)
  end)

  it("marks the readiness of running pods with unready containers as pending", function()
    local data = vim.json.decode(t.fixture("pods.json"))
    data.items[1].status.containerStatuses[1].ready = false
    local highlights = formatters.pods.format(data)[1].highlights
    t.eq("KubeRunning", highlights.STATUS)
    t.eq("KubePending", highlights.READY)
  end)

  it("shows the reason of failing containers, like kubectl", function()
    local function status_of(mutate)
      local data = vim.json.decode(t.fixture("pods.json"))
      mutate(data.items[1])
      local row = formatters.pods.format(data)[1]
      return { row.row[4], row.highlights.STATUS }
    end
    t.eq(
      { "CrashLoopBackOff", "KubeFailed" },
      status_of(function(pod)
        pod.status.containerStatuses[2].state = { waiting = { reason = "CrashLoopBackOff" } }
      end)
    )
    t.eq(
      { "Error", "KubeFailed" },
      status_of(function(pod)
        pod.status.containerStatuses[1].state = { terminated = { exitCode = 1, reason = "Error" } }
      end)
    )
    t.eq(
      { "Init:0/1", "KubePending" },
      status_of(function(pod)
        pod.status.initContainerStatuses[1].state = { running = {} }
      end)
    )
    t.eq(
      { "Init:ImagePullBackOff", "KubeFailed" },
      status_of(function(pod)
        pod.status.initContainerStatuses[1].state = { waiting = { reason = "ImagePullBackOff" } }
      end)
    )
    t.eq(
      { "Running", "KubeRunning" },
      status_of(function(pod)
        -- A started sidecar does not block the pod
        pod.spec.initContainers[1].restartPolicy = "Always"
        pod.status.initContainerStatuses[1].started = true
        pod.status.initContainerStatuses[1].state = { running = {} }
      end)
    )
    t.eq(
      { "Evicted", "KubeFailed" },
      status_of(function(pod)
        pod.status.phase = "Failed"
        pod.status.reason = "Evicted"
        pod.status.containerStatuses = nil
      end)
    )
  end)

  it("reports a pod that is not ready once", function()
    local data = vim.json.decode(t.fixture("pods.json"))
    data.items[1].status.conditions = { { type = "Ready", status = "False", message = "containers not ready" } }
    t.eq(
      { { message = "The pod is not ready: containers not ready", severity = vim.diagnostic.severity.ERROR } },
      formatters.pods.format(data)[1].diagnostics
    )
  end)
end)

describe("containers formatter", function()
  it("lists init containers first, with status, restarts and ports", function()
    local result = rows("containers", "pod-web-1.json")
    t.eq({ "init", "init", "Completed", "0", "busybox:1", "" }, result[1].row)
    t.eq({ "app", "main", "Running", "1", "web:1", "8080/TCP, 9090/TCP" }, result[2].row)
    t.eq({ "sidecar", "main", "Running", "2", "proxy:1", "" }, result[3].row)
    t.eq({ STATUS = "KubeSucceeded" }, result[1].highlights)
    t.eq({ STATUS = "KubeRunning", RESTARTS = "KubePending" }, result[2].highlights)
    t.eq("app", result[2].item.name)
  end)

  it("reports unknown when there is no status", function()
    t.eq("Unknown", rows("containers", "pod-web-2.json")[1].row[3])
  end)

  it("shows the reason of waiting and terminated containers, and sidecars", function()
    local pod = vim.json.decode(t.fixture("pod-web-1.json"))
    pod.spec.initContainers[1].restartPolicy = "Always"
    pod.status.containerStatuses[1].state = { waiting = { reason = "CrashLoopBackOff" } }
    pod.status.containerStatuses[2].state = { terminated = { exitCode = 137, reason = "OOMKilled" } }
    local result = formatters.containers.format(pod)
    t.eq("sidecar", result[1].row[2])
    t.eq({ "CrashLoopBackOff", "KubeFailed" }, { result[2].row[3], result[2].highlights.STATUS })
    t.eq({ "OOMKilled", "KubeFailed" }, { result[3].row[3], result[3].highlights.STATUS })
  end)
end)

describe("deployments formatter", function()
  it("formats replica counts, DESIRED from the spec", function()
    t.eq({ "ns1", "web", "1/2", "3", "2", "1" }, vim.list_slice(rows("deployments", "deployments.json")[1].row, 1, 6))
  end)
end)

describe("nodes formatter", function()
  it("shows readiness and cordoned nodes, like kubectl", function()
    local data = vim.json.decode(t.fixture("nodes.json"))
    data.items[2].spec.unschedulable = true
    data.items[2].status.conditions =
      { { type = "MemoryPressure", status = "False" }, { type = "Ready", status = "False" } }
    local result = formatters.nodes.format(data)
    t.eq({ "Ready", "KubeRunning" }, { result[1].row[2], result[1].highlights.STATUS })
    t.eq({ "NotReady,SchedulingDisabled", "KubeFailed" }, { result[2].row[2], result[2].highlights.STATUS })
    t.eq(vim.diagnostic.severity.ERROR, result[2].diagnostics[1].severity)
  end)
end)

describe("jobs formatter", function()
  it("formats status, completions and duration, like kubectl", function()
    local result = rows("jobs", "jobs.json")
    t.eq({ "ns1", "migrate", "Complete", "1/1", "1m5s" }, vim.list_slice(result[1].row, 1, 5))
    t.eq({ STATUS = "KubeSucceeded" }, result[1].highlights)
    t.eq({ "ns1", "backup", "Failed", "0/1 of 2" }, vim.list_slice(result[2].row, 1, 4))
    t.eq({
      { message = "Job has reached the specified backoff limit", severity = vim.diagnostic.severity.ERROR },
    }, result[2].diagnostics)
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

describe("format_table with wide characters", function()
  it("aligns and truncates by display width", function()
    local _, formatted = resources.format_table(
      { "NAME", "AGE" },
      { { row = { "中文", "1d" }, item = {} }, { row = { "abcde", "2d" }, item = {} } }
    )
    t.eq("中文   1d ", formatted[1].formatted)
    t.eq("abcde  2d ", formatted[2].formatted)
    t.eq({ { 0, 7 }, { 9, 12 } }, formatted[1].ranges)
    t.eq(string.rep("中", 48) .. "...", resources.align_row({ string.rep("中", 60) }, { 120 }))
  end)
end)
