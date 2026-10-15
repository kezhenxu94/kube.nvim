local kubectl = require("kubectl")
local t = require("helpers")

---Run an async kubectl function and wait for its callback.
---@return {result: any, errors: string[]}
local function run(fn, ...)
  local done, result = false, nil
  local errors = {}
  local n = select("#", ...)
  local args = { ... }
  args[n + 1] = function(data)
    result, done = data, true
  end
  args[n + 2] = function(data)
    table.insert(errors, data)
  end
  fn(unpack(args, 1, n + 2))
  t.wait_for(function()
    return done
  end, "kubectl callback")
  return { result = result, errors = errors }
end

describe("kubectl", function()
  before_each(function()
    t.reset_kubectl()
    _G.kube.context = nil
  end)

  describe("argument building", function()
    before_each(function()
      t.respond("*", { stdout = "ok" })
    end)

    it("get lists across all namespaces", function()
      run(kubectl.get, "ctx", "pods", nil, "all", { selector = "app=web,tier=fe" })
      t.eq({ "--context ctx get pods -o json --all-namespaces --selector=app=web,tier=fe" }, t.calls())
    end)

    it("get a named resource in a namespace", function()
      run(kubectl.get, "ctx", "pod", "web-1", "ns1", nil)
      t.eq({ "--context ctx get pod -o json web-1 -n ns1" }, t.calls())
    end)

    it("describe", function()
      run(kubectl.describe, "ctx", "deployment.apps", "web", "ns1")
      t.eq({ "--context ctx describe deployment.apps web -n ns1" }, t.calls())
    end)

    it("omits -n for cluster-scoped resources", function()
      run(kubectl.describe, "ctx", "node", "n1", "all")
      run(kubectl.get_resource_yaml, "ctx", "Node", "n1", nil)
      t.eq({ "--context ctx describe node n1", "--context ctx get node n1 -o yaml" }, t.calls())
    end)

    it("delete", function()
      run(kubectl.delete, "ctx", "gateway.networking.istio.io", "gw", "istio-system")
      t.eq({ "--context ctx delete gateway.networking.istio.io gw -n istio-system" }, t.calls())
    end)

    it("apply", function()
      run(kubectl.apply, "ctx", "ns1", "/tmp/x.yaml")
      t.eq({ "--context ctx -n ns1 apply -f /tmp/x.yaml" }, t.calls())
    end)

    it("set image", function()
      run(kubectl.set_image, "ctx", "deployment.apps", "web", "ns1", "app", "web:2")
      t.eq({ "--context ctx set image deployment.apps/web app=web:2 -n ns1" }, t.calls())
    end)

    it("port-forward", function()
      run(kubectl.forward_port, "ctx", "pod", "web-1", "ns1", 8080, 18080)
      t.eq({ "--context ctx port-forward pod/web-1 18080:8080 -n ns1" }, t.calls())
    end)

    it("without a context uses the kubeconfig current-context", function()
      run(kubectl.get, nil, "pods", nil, "all", nil)
      t.eq({ "get pods -o json --all-namespaces" }, t.calls())
    end)

    it("scale, rollout, node operations and patch", function()
      run(kubectl.scale, "ctx", "deployment.apps", "web", "ns1", 3)
      run(kubectl.rollout, "ctx", "restart", "statefulset.apps", "db", "ns1")
      run(kubectl.node, "ctx", "cordon", "node-1")
      run(kubectl.node, "ctx", "drain", "node-1")
      run(kubectl.patch, "ctx", "secret", "db", "ns1", { data = { a = vim.NIL } })
      t.eq({
        "--context ctx scale deployment.apps/web --replicas=3 -n ns1",
        "--context ctx rollout restart statefulset.apps/db -n ns1",
        "--context ctx cordon node-1",
        "--context ctx drain node-1 --ignore-daemonsets --delete-emptydir-data",
        '--context ctx patch secret db --type=merge -p {"data":{"a":null}} -n ns1',
      }, t.calls())
    end)

    it("sets a request timeout except for streams", function()
      run(kubectl.get, "ctx", "pods", nil, "ns1", nil)
      run(kubectl.forward_port, "ctx", "pod", "web-1", "ns1", 8080, 18080)
      run(kubectl.node, "ctx", "drain", "node-1")
      local raw = t.calls(true)
      t.ok(raw[1]:find("--request-timeout=30s", 1, true), raw[1])
      t.ok(not raw[2]:find("--request-timeout", 1, true), raw[2])
      t.ok(not raw[3]:find("--request-timeout", 1, true), raw[3])
    end)

    it("keeps arguments with spaces intact", function()
      run(kubectl.get, "my ctx", "pods", nil, "ns1", { selector = "env in (a, b)" })
      t.eq(1, #t.calls_matching("^%-%-context my ctx get pods %-o json %-n ns1 %-%-selector=env in %(a, b%)$"))
    end)
  end)

  describe("exec_cmd", function()
    it("puts the container before the command", function()
      t.eq({
        "kubectl",
        "--context",
        "ctx",
        "exec",
        "-it",
        "pod/web-1",
        "-n",
        "ns1",
        "-c",
        "app",
        "--",
        "sh",
        "-c",
        "command -v bash >/dev/null && exec bash || exec sh",
      }, kubectl.exec_cmd("ctx", "Pod", "web-1", "ns1", "app"))
    end)

    it("omits the container when not given", function()
      local cmd = kubectl.exec_cmd("ctx", "service", "web", "ns1", nil)
      t.eq({ "--", "sh", "-c" }, vim.list_slice(cmd, 9, 11))
      t.eq("service/web", cmd[6])
    end)
  end)

  describe("results", function()
    it("passes stdout on success", function()
      t.respond("*describe*", { stdout = "Name: web\n" })
      local out = run(kubectl.describe, "ctx", "pod", "web", "ns1")
      t.eq("Name: web\n", out.result)
      t.eq({}, out.errors)
    end)

    it("passes stderr to on_error and nil to callback on failure", function()
      t.respond("*delete*", { stderr = "Error from server (NotFound)", code = 1 })
      local out = run(kubectl.delete, "ctx", "pod", "web", "ns1")
      t.eq(nil, out.result)
      t.eq({ "Error from server (NotFound)" }, out.errors)
    end)

    it("ignores warnings on stderr when the command succeeds", function()
      t.respond("*apply*", { stdout = "configured", stderr = "Warning: deprecated" })
      local out = run(kubectl.apply, "ctx", "ns1", "/tmp/x.yaml")
      t.eq("configured", out.result)
      t.eq({}, out.errors)
    end)

    it("diff treats exit code 1 (differences) as success", function()
      t.respond("*diff*", { stdout = "-a\n+b\n", code = 1 })
      t.eq("-a\n+b\n", run(kubectl.diff, "ctx", "ns1", "/tmp/x.yaml").result)
      t.respond("*diff*", { stdout = "", code = 0 })
      t.eq("", run(kubectl.diff, "ctx", "ns1", "/tmp/x.yaml").result)
      t.respond("*diff*", { stderr = "error: invalid object", code = 2 })
      local out = run(kubectl.diff, "ctx", "ns1", "/tmp/x.yaml")
      t.eq(nil, out.result)
      t.eq({ "error: invalid object" }, out.errors)
    end)

    it("runs callbacks on the main loop", function()
      t.respond("*", { stdout = "ok" })
      local fast
      kubectl.describe("ctx", "pod", "web", "ns1", function()
        fast = vim.in_fast_event()
      end)
      t.wait_for(function()
        return fast ~= nil
      end)
      t.eq(false, fast)
    end)
  end)

  describe("logs", function()
    it("returns the whole output without the trailing newline", function()
      t.respond("*logs*", { stdout = "line1\nline2\n" })
      local lines
      kubectl.logs("ctx", "pod", "web-1", "ns1", { container = "app" }, function(data)
        lines = data
      end)
      t.wait_for(function()
        return lines
      end)
      t.eq("line1\nline2", lines)
      t.eq({ "--context ctx logs pod/web-1 -c app -n ns1 --tail=1000" }, t.calls())
    end)

    it("passes previous, all containers, since and tail", function()
      t.respond("*logs*", { stdout = "x" })
      local done = false
      kubectl.logs(
        "ctx",
        "deployment.apps",
        "web",
        "ns1",
        { previous = true, all_containers = true, since = "1h", tail = -1 },
        function()
          done = true
        end
      )
      t.wait_for(function()
        return done
      end)
      t.eq(
        { "--context ctx logs deployment.apps/web -n ns1 --tail=-1 --previous --all-containers --since=1h" },
        t.calls()
      )
    end)

    it("shows errors in place of the logs", function()
      t.respond("*logs*", { stderr = "container not found", code = 1 })
      local lines
      kubectl.logs("ctx", "pod", "web-1", "ns1", {}, function(data)
        lines = data
      end)
      t.wait_for(function()
        return lines
      end)
      t.eq("container not found", lines)
    end)

    it("streams complete lines when following", function()
      t.respond("*logs*", { script = "printf 'a\\nb'; sleep 0.2; printf 'c\\nd\\n'" })
      local chunks = {}
      local job = kubectl.logs("ctx", "pod", "web-1", "ns1", { follow = true }, function(data)
        table.insert(chunks, data)
      end)
      t.wait_for(function()
        return job:is_closing() and #chunks == 2
      end, "log chunks")
      t.eq({ "a", "bc\nd" }, chunks)
      t.eq({ "--context ctx logs pod/web-1 -n ns1 --tail=1000 -f" }, t.calls())
    end)

    it("flushes a final partial line when the stream ends", function()
      t.respond("*logs*", { script = "printf 'a\\nb'" })
      local chunks = {}
      kubectl.logs("ctx", "pod", "web-1", "ns1", { follow = true }, function(data)
        table.insert(chunks, data)
      end)
      t.wait_for(function()
        return #chunks == 2
      end, "log chunks")
      t.eq({ "a", "b" }, chunks)
    end)
  end)

  describe("kill", function()
    it("kills running jobs and ignores finished ones", function()
      t.respond("*", { script = "sleep 30" })
      local job = assert(kubectl.describe("ctx", "pod", "web", "ns1", function() end))
      kubectl.kill(job)
      t.wait_for(function()
        return job:is_closing()
      end, "job to exit")
      kubectl.kill(job)
      kubectl.kill(nil)
    end)
  end)

  describe("contexts", function()
    it("prefers the context switched to in Neovim", function()
      t.respond("*current-context*", { stdout = "from-kubeconfig\n" })
      t.eq("from-kubeconfig", kubectl.get_current_context())
      _G.kube.context = "local"
      t.eq("local", kubectl.get_current_context())
    end)

    it("does not cache the kubeconfig current-context", function()
      t.respond("*current-context*", { stdout = "a\n" })
      t.eq("a", kubectl.get_current_context())
      t.respond("*current-context*", { stdout = "b\n" })
      t.eq("b", kubectl.get_current_context())
    end)

    it("returns nil without a current-context", function()
      t.respond("*current-context*", { stderr = "error: current-context is not set", code = 1 })
      t.eq(nil, kubectl.get_current_context())
    end)

    it("lists context names", function()
      t.respond("*get-contexts*", { stdout = "a\nb\n" })
      t.eq({ "a", "b" }, kubectl.context_names_sync())
    end)

    it("persists the switched context", function()
      kubectl.use_context("saved-ctx", function() end)
      _G.kube = nil
      package.loaded.kubectl = nil
      kubectl = require("kubectl")
      t.eq("saved-ctx", _G.kube.context)
    end)

    it("ignores a corrupt state file", function()
      vim.fn.writefile({ "{not json" }, vim.fn.stdpath("state") .. "/kube_state.json")
      _G.kube = nil
      package.loaded.kubectl = nil
      kubectl = require("kubectl")
      t.eq(nil, _G.kube.context)
    end)
  end)

  describe("api_resources_sync", function()
    it("caches per context and does not cache failures", function()
      t.respond("*api-resources*", { stderr = "unreachable", code = 1 })
      t.eq({}, kubectl.api_resources_sync())
      t.respond("*api-resources*", { stdout = "pods\ndeployments.apps\n" })
      t.eq({ "pods", "deployments.apps" }, kubectl.api_resources_sync())
      t.eq({ "pods", "deployments.apps" }, kubectl.api_resources_sync())
      t.eq(2, #t.calls_matching("api%-resources"))

      _G.kube.context = "other"
      kubectl.api_resources_sync()
      t.eq(1, #t.calls_matching("^%-%-context other api%-resources"))
    end)
  end)
end)
