SHELL := bash
.SHELLFLAGS := -euo pipefail -c

SHELLCHECK_VERSION := 0.11.0
ACTIONLINT_VERSION := 1.7.12
LILBEE_REPO ?= https://github.com/tobocop2/lilbee

# The lilbee tests that read the cells file and the build workflow.
LILBEE_TESTS := tests/test_ik_llama_adapter.py tests/test_llama_pack_backend.py \
  tests/test_mistralrs_pack_tools.py tests/test_pack_workflow_helper.py \
  tests/test_source_date_epoch.py tests/test_tei_wheel_tools.py \
  tests/providers/fleet/test_engine_store.py

ENGINE ?= all
CELL ?=

.PHONY: plan tools lint test test-lilbee check

# Print the matrix JSON that build-packs.yml uses: make plan ENGINE=tei CELL=tei-linux-x86_64-cpu
plan:
	@bash scripts/plan.sh "$(ENGINE)" "$(CELL)"

# Fail when a tool is missing or has another version. Nothing is skipped.
tools:
	@for tool in bats git jq uv yq; do \
	  command -v "$$tool" >/dev/null || { echo "make: $$tool is not installed" >&2; exit 1; }; \
	done
	@shellcheck --version 2>/dev/null | grep -qx 'version: $(SHELLCHECK_VERSION)' \
	  || { echo "make: shellcheck $(SHELLCHECK_VERSION) is required (scripts/install_lint_tools.sh installs it)" >&2; exit 1; }
	@actionlint --version 2>/dev/null | head -n 1 | grep -qx '$(ACTIONLINT_VERSION)' \
	  || { echo "make: actionlint $(ACTIONLINT_VERSION) is required (scripts/install_lint_tools.sh installs it)" >&2; exit 1; }

lint: tools
	shellcheck scripts/*.sh tests/*.bash tests/stubs/*
	actionlint .github/workflows/*.yml

test: tools
	bats tests/

# Run the lilbee tests at the tag in LILBEE_REF against the cells file and the workflow of this checkout.
# LILBEE_DIR names a lilbee tree to use; it must be at the commit of the tag.
test-lilbee: tools
	@out="$$(bash scripts/lilbee_ref.sh LILBEE_REF)"; \
	tag="$$(sed -n 's/^tag=//p' <<< "$$out")"; \
	commit="$$(sed -n 's/^commit=//p' <<< "$$out")"; \
	dir="$${LILBEE_DIR:-.work/lilbee-$$commit}"; \
	if [ ! -d "$$dir" ]; then \
	  git clone --quiet --depth 1 --branch "$$tag" "$(LILBEE_REPO)" "$$dir"; \
	fi; \
	[ "$$(git -C "$$dir" rev-parse HEAD)" = "$$commit" ] \
	  || { echo "make: $$dir is not at commit $$commit of the tag $$tag" >&2; exit 1; }; \
	grep -q 'def pack_cells' "$$dir/tests/_pack_workflow.py" \
	  || { echo "make: the lilbee tag $$tag has no pack_cells in tests/_pack_workflow.py. Name a newer tag in LILBEE_REF." >&2; exit 1; }; \
	here="$$(pwd)"; \
	cd "$$dir"; \
	uv sync --locked; \
	ENGINE_PACKS_CELLS="$$here/cells.yml" ENGINE_PACKS_WORKFLOW="$$here/.github/workflows/build-packs.yml" \
	  uv run pytest -p no:cacheprovider -q $(LILBEE_TESTS)

check: lint test test-lilbee
