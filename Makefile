NVIM ?= nvim
SPECS ?= $(wildcard tests/*_spec.lua)

.PHONY: test lint format

# Each spec runs in its own Neovim with isolated state, against tests/bin/kubectl (never a real cluster)
test:
	@failed=0; for spec in $(SPECS); do \
		tmp=$$(mktemp -d); \
		XDG_STATE_HOME=$$tmp/state XDG_DATA_HOME=$$tmp/data XDG_CONFIG_HOME=$$tmp/config KUBECONFIG=$$tmp/kubeconfig \
			$(NVIM) --headless --clean -l tests/runner.lua $$spec || failed=1; \
		rm -rf $$tmp; \
	done; exit $$failed

lint:
	stylua --check lua tests plugin

format:
	stylua lua tests plugin

# End-to-end tests against a kind cluster with its own kubeconfig, never the user's
E2E_CLUSTER ?= kube-nvim-e2e
E2E_KUBECONFIG ?= $(CURDIR)/.e2e-kubeconfig

.PHONY: e2e-cluster test-e2e e2e-clean

e2e-cluster:
	KUBECONFIG=$(E2E_KUBECONFIG) KIND_CLUSTER=$(E2E_CLUSTER) tests/e2e/setup.sh

test-e2e: e2e-cluster
	@failed=0; for spec in tests/e2e/*_spec.lua; do \
		tmp=$$(mktemp -d); \
		XDG_STATE_HOME=$$tmp/state XDG_DATA_HOME=$$tmp/data XDG_CONFIG_HOME=$$tmp/config \
		KUBECONFIG=$(E2E_KUBECONFIG) KUBE_E2E_CONTEXT=kind-$(E2E_CLUSTER) \
			$(NVIM) --headless --clean -l tests/runner.lua $$spec || failed=1; \
		rm -rf $$tmp; \
	done; exit $$failed

# The README demo: a kind cluster with its own kubeconfig, recorded with asciinema in tmux.
# The GIF is in the repo as GitHub cannot proxy images of asciinema.org.
.PHONY: demo
demo:
	demo/setup.sh
	demo/record.sh
	agg demo/kube-nvim.cast demo/kube-nvim.gif

e2e-clean:
	KUBECONFIG=$(E2E_KUBECONFIG) kind delete cluster --name $(E2E_CLUSTER)
	rm -f $(E2E_KUBECONFIG)
