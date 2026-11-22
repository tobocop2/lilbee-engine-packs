#!/usr/bin/env bats
# scripts/plan.sh: the matrix of each job of build-packs.yml, from cells.yml.

load helpers

setup() {
  use_stubs
  SCRIPT="${REPO_ROOT}/scripts/plan.sh"
  CELLS="${REPO_ROOT}/cells.yml"
  FIXTURE="${BATS_TEST_TMPDIR}/cells.yml"
  cat > "${FIXTURE}" << 'EOF'
engines:
  llama:
    cells:
      - {cell: win-cpu, build_number: 4, backend: cpu, timeout: 45}
      - {cell: linux-cpu, build_number: 3, backend: cpu, build: source}
  mistralrs:
    cells:
      - {cell: mistralrs-linux, backend: cpu}
  tei:
    cells:
      - {cell: tei-cpu, cc: '75', os: linux}
  ik:
    cells:
      - {cell: linux-cpu, build_number: 4}
EOF
}

count() {  # engine
  jq -r --arg e "$1" '.[$e] | length' <<< "$output"
}

@test "all selects llama and mistralrs and leaves tei and ik empty" {
  run bash "${SCRIPT}" all "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 8 ]
  [ "$(count mistralrs)" -eq 3 ]
  [ "$(count tei)" -eq 0 ]
  [ "$(count ik)" -eq 0 ]
}

@test "no argument means all" {
  cd "${REPO_ROOT}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(count llama)" -eq 8 ]
  [ "$(count tei)" -eq 0 ]
}

@test "tei runs only by name" {
  run bash "${SCRIPT}" tei "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count tei)" -eq 9 ]
  [ "$(count llama)" -eq 0 ]
  [ "$(count mistralrs)" -eq 0 ]
  [ "$(count ik)" -eq 0 ]
}

@test "ik runs only by name" {
  run bash "${SCRIPT}" ik "" "${CELLS}"
  [ "$status" -eq 0 ]
  [ "$(count ik)" -eq 2 ]
  [ "$(count llama)" -eq 0 ]
}

@test "an unknown engine fails and names the choices" {
  run bash "${SCRIPT}" openvino "" "${CELLS}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown engine 'openvino'"* ]]
}

@test "the output for a fixture is exactly the expected JSON" {
  run bash "${SCRIPT}" all "" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ "$output" = '{"llama":[{"cell":"win-cpu","build_number":4,"backend":"cpu","timeout":45},{"cell":"linux-cpu","build_number":3,"backend":"cpu","build":"source"}],"mistralrs":[{"cell":"mistralrs-linux","backend":"cpu"}],"tei":[],"ik":[]}' ]
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
  [ "$(count ik)" -eq 0 ]
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
