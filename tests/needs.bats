#!/usr/bin/env bats
# scripts/needs_ok.sh: the publish job runs only when the plan succeeded, every job that the plan gave cells
# succeeded, and every other job succeeded or was skipped on purpose.

load helpers

setup() {
  use_stubs
  SCRIPT="${REPO_ROOT}/scripts/needs_ok.sh"
  # The engines that the plan gives cells, as the plan job lists them in its outputs.
  PLANNED="llama mistralrs"
}

# needs <plan> <cell> <mistralrs> <tei> <ik> [mlx]: the toJSON(needs) of the publish job, with these results.
# The mlx job is skipped when the call gives it no result.
# The plan outputs give one cell to each engine of PLANNED and none to the others.
needs() {
  jq -cn --arg planned "${PLANNED}" --args '[$ARGS.positional[]] as $r
    | ($planned | split(" ") | map(select(. != ""))) as $p
    | {plan: {result: $r[0], outputs: ({llama: "[]", mistralrs: "[]", tei: "[]", ik: "[]", mlx: "[]", any: "false"}
        + ([$p[] | {key: ., value: "[{\"cell\":\"x\"}]"}] | from_entries)
        + {any: (if $p == [] then "false" else "true" end)})},
       cell: {result: $r[1]}, mistralrs: {result: $r[2]}, tei: {result: $r[3]}, ik: {result: $r[4]},
       mlx: {result: ($r[5] // "skipped")}}' "$@"
}

@test "every job that the plan gave cells succeeded and the others are skipped" {
  run bash "${SCRIPT}" "$(needs success success success skipped skipped)"
  [ "${status}" -eq 0 ]
}

@test "the plan gave cells to tei alone, which succeeded, and the other jobs are skipped" {
  PLANNED="tei"
  run bash "${SCRIPT}" "$(needs success skipped skipped success skipped)"
  [ "${status}" -eq 0 ]
}

@test "the plan gave cells to mlx alone, which succeeded, and the other jobs are skipped" {
  PLANNED="mlx"
  run bash "${SCRIPT}" "$(needs success skipped skipped skipped skipped success)"
  [ "${status}" -eq 0 ]
}

@test "a failed mlx job blocks the publish" {
  PLANNED="mlx"
  run bash "${SCRIPT}" "$(needs success skipped skipped skipped skipped failure)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mlx: failure"* ]]
}

@test "the plan gave cells to ik alone, as a run of all does when only ik is not published" {
  PLANNED="ik"
  run bash "${SCRIPT}" "$(needs success skipped skipped skipped success)"
  [ "${status}" -eq 0 ]
}

@test "one cancelled job blocks the publish" {
  run bash "${SCRIPT}" "$(needs success cancelled success skipped skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cell: cancelled"* ]]
}

@test "one failed job blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success failure skipped skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mistralrs: failure"* ]]
}

@test "a cancelled job that the plan gave no cell blocks the publish" {
  PLANNED="llama"
  run bash "${SCRIPT}" "$(needs success success skipped cancelled skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"tei: cancelled"* ]]
}

@test "a failed plan job blocks the publish" {
  run bash "${SCRIPT}" "$(needs failure skipped skipped skipped skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"plan: failure"* ]]
}

@test "a plan that gives no job a cell does not publish" {
  PLANNED=""
  run bash "${SCRIPT}" "$(needs success skipped skipped skipped skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"the plan gives no job a cell"* ]]
}

@test "a job that the plan gave cells and GitHub skipped blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success skipped skipped skipped)"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mistralrs: skipped, and the plan gives it cells"* ]]
}

@test "needs without the plan job block the publish" {
  run bash "${SCRIPT}" '{"cell":{"result":"success"}}'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"plan: missing"* ]]
}

@test "a job that the plan gave cells and the needs do not list blocks the publish" {
  run bash "${SCRIPT}" "$(needs success success success skipped skipped | jq -c 'del(.mistralrs)')"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"mistralrs: missing, and the plan gives it cells"* ]]
}

@test "the lilbee commit and the any output of the plan are not jobs" {
  run bash "${SCRIPT}" "$(needs success success success skipped skipped | jq -c '.plan.outputs.lilbee_ref = "abc"')"
  [ "${status}" -eq 0 ]
}

@test "a missing argument is refused" {
  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"usage: needs_ok.sh"* ]]
}

@test "a missing jq blocks the publish and the message names jq" {
  local json
  json="$(needs success success success skipped skipped)"
  run env PATH="${BATS_TEST_TMPDIR}" /bin/bash "${SCRIPT}" "${json}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"needs_ok: jq is not installed, so the release is not published."* ]]
}

@test "the publish job runs the check before it uploads, and passes the needs alone" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  run yq '.jobs.publish.steps[] | select(.run != null) | .run' "${workflow}"
  [ "${status}" -eq 0 ]
  [ "$(head -n 1 <<< "${output}")" = 'bash scripts/needs_ok.sh "${NEEDS}"' ]
  [ "$(yq -o=json -I=0 '.jobs.publish.steps[] | select(.run == "bash scripts/needs_ok.sh \"${NEEDS}\"") | .env' "${workflow}")" = '{"NEEDS":"${{ toJSON(needs) }}"}' ]
}

@test "the publish job needs every build job" {
  run yq -r '.jobs.publish.needs | join(" ")' "${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "${output}" = "plan cell mistralrs tei ik mlx" ]
}

@test "the check reads the plan output of each build job, and the plan job lists one for each engine" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml" engine job
  for engine in $(yq -r '.engines | keys | .[]' "${REPO_ROOT}/cells.yml"); do
    job="${engine}"
    [ "${engine}" != llama ] || job=cell
    [ "$(yq -r ".jobs.plan.outputs.${engine}" "${workflow}")" = "\${{ steps.plan.outputs.${engine} }}" ]
    [ "$(yq -r ".jobs.${job}.needs" "${workflow}")" = plan ]
  done
}
