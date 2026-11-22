#!/usr/bin/env bats
# scripts/lilbee_ref.sh: the lilbee tag that LILBEE_REF names, and its commit.

load helpers

setup() {
  use_stubs git
  unset LILBEE_REPO LILBEE_DEV
  SCRIPT="${REPO_ROOT}/scripts/lilbee_ref.sh"
  REF_FILE="${BATS_TEST_TMPDIR}/LILBEE_REF"
  TAG_SHA="1111111111111111111111111111111111111111"
  COMMIT_SHA="2222222222222222222222222222222222222222"
}

@test "a lightweight tag gives its own sha as the commit" {
  printf 'engine-packs-pin-9\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="${TAG_SHA}	refs/tags/engine-packs-pin-9"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ref=refs/tags/engine-packs-pin-9" ]
  [ "${lines[1]}" = "tag=engine-packs-pin-9" ]
  [ "${lines[2]}" = "commit=${TAG_SHA}" ]
}

@test "an annotated tag gives the peeled commit, not the tag object" {
  printf 'engine-packs-pin-9\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="${TAG_SHA}	refs/tags/engine-packs-pin-9
${COMMIT_SHA}	refs/tags/engine-packs-pin-9^{}"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "commit=${COMMIT_SHA}" ]
}

@test "the script asks the lilbee repository for the tag and its peeled form" {
  printf 'engine-packs-pin-9\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="${TAG_SHA}	refs/tags/engine-packs-pin-9"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 0 ]
  [ "$(cat "${STUB_GIT_LOG}")" = "ls-remote --exit-code --tags https://github.com/tobocop2/lilbee refs/tags/engine-packs-pin-9 refs/tags/engine-packs-pin-9^{}" ]
}

@test "white space around the name is dropped" {
  printf '  engine-packs-pin-9  \n\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="${TAG_SHA}	refs/tags/engine-packs-pin-9"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "tag=engine-packs-pin-9" ]
}

@test "a name that is not a tag name fails before any network call" {
  printf 'not a tag/name\n' > "${REF_FILE}"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must hold one lilbee tag name"* ]]
  [ ! -s "${STUB_GIT_LOG}" ]
}

@test "a tag that does not exist fails with the name in the message" {
  printf 'engine-packs-pin-99\n' > "${REF_FILE}"
  export STUB_GIT_RC=2
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"engine-packs-pin-99"*"does not exist"* ]]
}

@test "an answer that holds no commit fails" {
  printf 'engine-packs-pin-9\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="not-a-sha	refs/tags/engine-packs-pin-9"
  run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not resolve to a commit"* ]]
}

@test "LILBEE_REPO names another repository to ask" {
  printf 'engine-packs-pin-9\n' > "${REF_FILE}"
  export STUB_GIT_OUTPUT="${TAG_SHA}	refs/tags/engine-packs-pin-9"
  LILBEE_REPO=https://example.test/fork run bash "${SCRIPT}" "${REF_FILE}"
  [ "$status" -eq 0 ]
  [[ "$(cat "${STUB_GIT_LOG}")" == *"https://example.test/fork"* ]]
}

@test "the LILBEE_REF file of this repository holds a tag name" {
  [[ "$(tr -d '[:space:]' < "${REPO_ROOT}/LILBEE_REF")" =~ ^[A-Za-z0-9._-]+$ ]]
}
