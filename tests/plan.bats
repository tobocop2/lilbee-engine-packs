#!/usr/bin/env bats
# scripts/plan.sh: the matrix of each job of build-packs.yml, from cells.yml, without the published cells.

bats_require_minimum_version 1.5.0

load helpers

setup() {
  use_stubs
  unset CELL
  SCRIPT="${REPO_ROOT}/scripts/plan.sh"
  CELLS="${REPO_ROOT}/cells.yml"
  FIXTURE="${BATS_TEST_TMPDIR}/cells.yml"
  PUBLISHED="${BATS_TEST_TMPDIR}/published.txt"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary.md"
  : > "${PUBLISHED}"
  cat > "${FIXTURE}" << 'EOF'
engines:
  llama:
    pins: {WHEEL_VERSION: 1.2.3}
    cells:
      - {cell: win-cpu, build_number: 4, backend: cpu, platform: win_amd64, timeout: 45}
      - {cell: linux-cpu, build_number: 3, backend: cpu, platform: manylinux_2_34_x86_64, build: source}
  mistralrs:
    pins: {MISTRALRS_TAG: v0.9.5}
    cells:
      - {cell: mistralrs-linux, build_number: 2, backend: cuda-sm80, platform: manylinux_2_35_x86_64}
  tei:
    pins: {WHEEL_VERSION: 1.9.4}
    cells:
      - {cell: tei-cpu, build_number: 1, backend: cpu, cc: '75', os: linux, platform: manylinux_2_34_x86_64}
  ik:
    pins: {UPSTREAM_COMMIT: 13cffc006b82e03e4d89cbb8c7327f0255ae3d18, PLATFORM: manylinux_2_34_x86_64}
    cells:
      - {cell: linux-cpu, build_number: 4, backend: cpu}
EOF
}

count() {  # engine
  jq -r --arg e "$1" '.[$e] | length' <<< "$output"
}

# published <wheel> <tag>: a release ships the wheel.
published() {
  printf '%s %s\n' "$1" "$2" >> "${PUBLISHED}"
}

IK_WHEEL="lilbee_engine_ik_llama_cpp-0+git13cffc006b82-4.cpu-py3-none-manylinux_2_34_x86_64.whl"
WIN_WHEEL="lilbee_engine_llama_cpp-1.2.3-4.cpu-py3-none-win_amd64.whl"

@test "all selects every engine of the cells file" {
  run bash "${SCRIPT}" all "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 8 ]
  [ "$(count mistralrs)" -eq 9 ]
  [ "$(count tei)" -eq 9 ]
  [ "$(count ik)" -eq 2 ]
  [ "$(jq -r 'keys_unsorted | join(" ")' <<< "$output")" = "llama mistralrs tei ik" ]
}

@test "no argument means all" {
  cd "${REPO_ROOT}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 8 ]
  [ "$(count tei)" -eq 9 ]
}

@test "all selects an engine that the cells file adds, which needs a distribution in the name rule" {
  yq -i '.engines.extra = .engines.tei' "${FIXTURE}"
  run --separate-stderr bash "${SCRIPT}" all "" "${FIXTURE}"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"the engine extra has no distribution in scripts/wheel_name.bash"* ]]
}

@test "a name selects that engine alone" {
  run bash "${SCRIPT}" tei "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count tei)" -eq 9 ]
  [ "$(count llama)" -eq 0 ]
  [ "$(count mistralrs)" -eq 0 ]
  [ "$(count ik)" -eq 0 ]
}

@test "ik runs by name" {
  run bash "${SCRIPT}" ik "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 2 ]
  [ "$(count llama)" -eq 0 ]
}

@test "an unknown engine fails and names the engines of the cells file" {
  run bash "${SCRIPT}" openvino "" "${CELLS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown engine 'openvino'. Use all, llama, mistralrs, tei, ik."* ]]
}

@test "the output for a fixture is exactly the expected JSON" {
  run bash "${SCRIPT}" all "" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$output" = '{"llama":[{"cell":"win-cpu","build_number":4,"backend":"cpu","platform":"win_amd64","timeout":45},{"cell":"linux-cpu","build_number":3,"backend":"cpu","platform":"manylinux_2_34_x86_64","build":"source"}],"mistralrs":[{"cell":"mistralrs-linux","build_number":2,"backend":"cuda-sm80","platform":"manylinux_2_35_x86_64"}],"tei":[{"cell":"tei-cpu","build_number":1,"backend":"cpu","cc":"75","os":"linux","platform":"manylinux_2_34_x86_64"}],"ik":[{"cell":"linux-cpu","build_number":4,"backend":"cpu"}]}' ]
}

@test "a value that is a string in the file stays a string" {
  run bash "${SCRIPT}" tei "" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tei[0].cc | type' <<< "$output")" = "string" ]
}

@test "a number in the file stays a number" {
  run bash "${SCRIPT}" ik "" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ik[0].build_number | type' <<< "$output")" = "number" ]
}

@test "the output is one line, which a step output requires" {
  run bash "${SCRIPT}" all "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a cell name narrows the run to that cell" {
  run bash "${SCRIPT}" llama win-cpu "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 1 ]
  [ "$(jq -r '.llama[0].cell' <<< "$output")" = "win-cpu" ]
}

@test "the engine name and the cell name joined by a dash select one cell" {
  run bash "${SCRIPT}" ik ik-linux-cpu "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 1 ]
}

@test "a cell name that two engines share narrows each selected engine" {
  run bash "${SCRIPT}" all linux-cpu "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 1 ]
  [ "$(count ik)" -eq 1 ]
  [ "$(count tei)" -eq 0 ]
}

@test "a cell that does not exist fails instead of selecting nothing" {
  run bash "${SCRIPT}" all no-such-cell "${CELLS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no cell"*"no-such-cell"* ]]
}

@test "a cell of an engine that is not selected fails" {
  run bash "${SCRIPT}" llama tei-linux-x86_64-cpu "${CELLS}"
  [ "$status" -eq 1 ]
}

@test "the cells keep the order of the file" {
  run bash "${SCRIPT}" llama "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.llama[0].cell' <<< "$output")" = "windows-x86_64-cpu" ]
  [ "$(jq -r '.llama[-1].cell' <<< "$output")" = "linux-x86_64-rocm" ]
}

@test "make plan prints the same JSON as the script" {
  cd "${REPO_ROOT}"
  run make --no-print-directory plan ENGINE=ik
  [ "$status" -eq 0 ]
  [ "$output" = "$(bash "${SCRIPT}" ik "" "${CELLS}")" ]
}

@test "a published cell is dropped, and stderr and the step summary name it and its release" {
  published "${IK_WHEEL}" engine-packs-20261119-ik
  run --separate-stderr bash "${SCRIPT}" all "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 0 ]
  [ "$(count llama)" -eq 2 ]
  [ "$(count mistralrs)" -eq 1 ]
  [ "$(count tei)" -eq 1 ]
  [[ "$stderr" == *"ik-linux-cpu: ${IK_WHEEL} is in the release engine-packs-20261119-ik"* ]]
  grep -qxF -- "- ik-linux-cpu: ${IK_WHEEL} is in the release engine-packs-20261119-ik" "${GITHUB_STEP_SUMMARY}"
}

@test "a cell one build above its published wheel is kept" {
  published "${IK_WHEEL/-4.cpu-/-3.cpu-}" engine-packs-20261119-ik
  run --separate-stderr bash "${SCRIPT}" ik "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 1 ]
  [ -z "$stderr" ]
  [ ! -s "${GITHUB_STEP_SUMMARY}" ]
}

@test "a name that is not a wheel of a cell drops nothing" {
  published "${IK_WHEEL}.sha256" engine-packs-1
  published "x${WIN_WHEEL}" engine-packs-1
  run --separate-stderr bash "${SCRIPT}" all "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 1 ]
  [ "$(count llama)" -eq 2 ]
}

@test "each engine gets the wheel name of its own rule" {
  published "${WIN_WHEEL}" r1
  published lilbee_engine_llama_cpp-1.2.3-3.cpu-py3-none-manylinux_2_34_x86_64.whl r1
  published lilbee_engine_mistral_rs-0.9.5-2.cuda_sm80-py3-none-manylinux_2_35_x86_64.whl r2
  published lilbee_engine_tei-1.9.4-1.cpu-py3-none-manylinux_2_34_x86_64.whl r3
  published "${IK_WHEEL}" r4
  run --separate-stderr bash "${SCRIPT}" all "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  [ "$output" = '{"llama":[],"mistralrs":[],"tei":[],"ik":[]}' ]
  [ "$(grep -c ' is in the release ' <<< "$stderr")" -eq 5 ]
}

@test "a run whose every cell is published plans no cell and does not fail" {
  run --separate-stderr bash "${SCRIPT}" ik "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  published "${IK_WHEEL}" r4
  run --separate-stderr bash "${SCRIPT}" ik "" "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 0 ]
}

@test "a run that names a published cell fails and asks for a new build number" {
  published "${IK_WHEEL}" engine-packs-20261119-ik
  run --separate-stderr bash "${SCRIPT}" ik ik-linux-cpu "${FIXTURE}" "${PUBLISHED}"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Raise its build number."* ]]
  [[ "$stderr" == *"ik-linux-cpu: ${IK_WHEEL} is in the release engine-packs-20261119-ik"* ]]
  [ -z "$output" ]
}

@test "a published file that does not exist fails the plan" {
  run bash "${SCRIPT}" all "" "${FIXTURE}" "${BATS_TEST_TMPDIR}/none.txt"
  [ "$status" -ne 0 ]
}

@test "a cell with no build number fails and names the cell" {
  yq -i 'del(.engines.ik.cells[0].build_number)' "${FIXTURE}"
  run --separate-stderr bash "${SCRIPT}" all "" "${FIXTURE}"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"the cell linux-cpu of ik has no build_number"* ]]
}

@test "a cell with no platform and an engine with no PLATFORM pin fails" {
  yq -i 'del(.engines.ik.pins.PLATFORM)' "${FIXTURE}"
  run --separate-stderr bash "${SCRIPT}" ik "" "${FIXTURE}"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"the cell linux-cpu of ik has no platform"* ]]
}

@test "an engine with no version pin fails" {
  yq -i 'del(.engines.tei.pins.WHEEL_VERSION)' "${FIXTURE}"
  run --separate-stderr bash "${SCRIPT}" tei "" "${FIXTURE}"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"the engine tei has no WHEEL_VERSION, MISTRALRS_TAG or UPSTREAM_COMMIT pin"* ]]
}
