VIM_BIN ?= vim
NVIM_BIN ?= nvim
SPECS ?= $(wildcard tests/*_spec.vim)
# The checkout of https://github.com/kezhenxu94/resource.vim
RESOURCE_VIM ?= ../resource.vim

.PHONY: test test-vim test-nvim

test: test-vim test-nvim

# Each spec runs in its own editor with isolated state, against tests/bin/kubectl (never a real cluster)
define run_specs
	@failed=0; for spec in $(2); do \
		tmp=$$(mktemp -d); \
		XDG_STATE_HOME=$$tmp/state XDG_DATA_HOME=$$tmp/data XDG_CONFIG_HOME=$$tmp/config KUBECONFIG=$$tmp/kubeconfig TZ=UTC RESOURCE_VIM=$(RESOURCE_VIM) $(3) KUBE_TEST_RESULT=$$tmp/result KUBE_TEST_OUT=$$tmp/out \
			$(1) --cmd "let g:spec = '$$spec'" -S tests/runner.vim < /dev/null > /dev/null; \
		cat $$tmp/out 2>/dev/null; test -f $$tmp/result || failed=1; \
		rm -rf $$tmp; \
	done; exit $$failed
endef

test-vim:
	$(call run_specs,$(VIM_BIN) -Nu NONE -i NONE --not-a-term,$(SPECS),)

test-nvim:
	$(call run_specs,$(NVIM_BIN) --headless -u NONE -i NONE,$(SPECS),)

# End-to-end tests against a kind cluster with its own kubeconfig, never the user's
E2E_CLUSTER ?= kube-nvim-e2e
E2E_KUBECONFIG ?= $(CURDIR)/.e2e-kubeconfig
E2E_ENV = KUBECONFIG=$(E2E_KUBECONFIG) KUBE_E2E_CONTEXT=kind-$(E2E_CLUSTER)

.PHONY: e2e-cluster test-e2e e2e-clean

e2e-cluster:
	KUBECONFIG=$(E2E_KUBECONFIG) KIND_CLUSTER=$(E2E_CLUSTER) tests/e2e/setup.sh

test-e2e: e2e-cluster
	$(call run_specs,$(VIM_BIN) -Nu NONE -i NONE --not-a-term,tests/e2e/e2e_spec.vim,$(E2E_ENV))
	$(call run_specs,$(NVIM_BIN) --headless -u NONE -i NONE,tests/e2e/e2e_spec.vim,$(E2E_ENV))

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
