#!/usr/bin/env bash
# Shared setup for the bats tests of the pack scripts.

# Find the repository root and put the stubs in front of the real tools.
# A test lists the stubs it needs: use_stubs git
use_stubs() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  STUB_GIT_LOG="${BATS_TEST_TMPDIR}/git.log"
  export STUB_GIT_LOG
  : > "${STUB_GIT_LOG}"
  mkdir -p "${STUB_BIN}"
  local tool
  for tool in "$@"; do
    ln -s "${REPO_ROOT}/tests/stubs/${tool}" "${STUB_BIN}/${tool}"
  done
  PATH="${STUB_BIN}:${PATH}"
}
