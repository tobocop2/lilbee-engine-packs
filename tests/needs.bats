#!/usr/bin/env bats
# scripts/needs_ok.sh: the publish job runs only when every needed job succeeded or was skipped on purpose,
# and every job of a selected engine succeeded.

load helpers

setup() {
  use_stubs
  SCRIPT="${REPO_ROOT}/scripts/needs_ok.sh"
}

# needs <plan> <cell> <mistralrs> <tei> <ik>: the toJSON(needs) of the publish job, with these results.
needs() {
  jq -cn --args '[$ARGS.positional[]] | {plan: {result: .[0]}, cell: {result: .[1]}, mistralrs: {result: .[2]}, tei: {result: .[3]}, ik: {result: .[4]}}' "$@"
}

@test "every job of the engine all succeeded" {
  run bash "${SCRIPT}" "$(needs success success success skipped skipped)" all
  [ "${status}" -eq 0 ]
}

@test "the engine tei alone succeeded and the other jobs are skipped" {
  run bash "${SCRIPT}" "$(needs success skipped skipped success skipped)" tei
  [ "${status}" -eq 0 ]
}

@test "one cancelled job blocks the publish" {
  run bash "${SCRIPT}" "$(needs success cancelled success skipped skipped)" all
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cell: cancelled"* ]]
}

@test "one failed job blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success failure skipped skipped)" all
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mistralrs: failure"* ]]
}

@test "a cancelled job of an engine that the run did not select blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success skipped cancelled skipped)" llama
  [ "${status}" -eq 1 ]
}

@test "a failed plan job blocks the publish" {
  run bash "${SCRIPT}" "$(needs failure skipped skipped skipped skipped)" all
  [ "${status}" -eq 1 ]
}

@test "a run where every job is skipped does not publish" {
  run bash "${SCRIPT}" "$(needs success skipped skipped skipped skipped)" all
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"the run selects it"* ]]
}

@test "a selected job that GitHub skipped blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success skipped skipped skipped)" all
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mistralrs: skipped"* ]]
}

@test "an unknown engine is refused" {
  run bash "${SCRIPT}" "$(needs success success success skipped skipped)" nope
  [ "${status}" -eq 1 ]
}

@test "the publish job runs the check before it uploads" {
  run yq '.jobs.publish.steps[] | select(.run != null) | .run' "${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "${status}" -eq 0 ]
  [[ "$(head -n 1 <<< "${output}")" == *"scripts/needs_ok.sh"* ]]
}

@test "the publish job needs every build job" {
  run yq -r '.jobs.publish.needs | join(" ")' "${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "${output}" = "plan cell mistralrs tei ik" ]
}
