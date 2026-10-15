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
	stylua --check lua tests

format:
	stylua lua tests
