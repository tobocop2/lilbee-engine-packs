#!/usr/bin/env bats
# scripts/pack.sh reads a cell, gets the lilbee tree of the tag and runs the recipe of the engine.
# The tests run a copy of the scripts beside their own cells file, against a real git repository
# that stands in for lilbee. Its recipes write the variables they receive to ${OUT}.

load helpers

setup() {
  use_stubs uname
  PACKS="${BATS_TEST_TMPDIR}/packs"
  mkdir -p "${PACKS}/scripts"
  cp "${REPO_ROOT}/scripts/pack.sh" "${REPO_ROOT}/scripts/lilbee_ref.sh" "${PACKS}/scripts/"
  SCRIPT="${PACKS}/scripts/pack.sh"
  echo pin-9 > "${PACKS}/LILBEE_REF"
  cat > "${PACKS}/cells.yml" <<'YML'
manylinux_image: quay.io/pypa/x@sha256:abc
engines:
  mistralrs:
    pins: {MISTRALRS_TAG: v0.9.5, MACOSX_DEPLOYMENT_TARGET: '14.0'}
    cells:
      - {cell: mistralrs-linux, backend: cpu, runner: ubuntu-22.04, platform: manylinux_2_35_x86_64, rust_target: t, timeout: 60}
      - {cell: mistralrs-mac, backend: metal, runner: macos-15, platform: macosx_11_0_arm64, rust_features: metal, timeout: 45}
      - {cell: mistralrs-win, backend: cpu, runner: windows-2022, platform: win_amd64, timeout: 45}
  llama:
    pins: {UPSTREAM_TAG: b1}
    cells:
      - {cell: linux-cpu, backend: cpu, platform: manylinux_2_34_x86_64, license: MIT AND BSD, build_number: 3}
  ik:
    pins: {PLATFORM: manylinux_2_34_x86_64}
    cells:
      - {cell: linux-cpu, backend: cpu, build_number: 4}
  tei:
    pins: {TEI_TAG: v1}
    cells:
      - {cell: tei-linux, os: linux, cc: '80', backend: cuda, platform: manylinux_2_34_x86_64}
YML
  export LILBEE_REPO="${BATS_TEST_TMPDIR}/lilbee-origin"
  mkdir -p "${LILBEE_REPO}/tools/wheel-build" "${LILBEE_REPO}/packaging"
  local recipe='env > "${OUT}/env.txt"; pwd > "${OUT}/pwd.txt"; umask > "${OUT}/umask.txt"; [ ! -e fail ]'
  local engine
  for engine in mistralrs ik tei; do
    printf '%s\n' "${recipe}" > "${LILBEE_REPO}/tools/wheel-build/pack_${engine}.sh"
  done
  echo 'dist/' > "${LILBEE_REPO}/.gitignore"
  echo wheel > "${LILBEE_REPO}/packaging/project"
  git -C "${LILBEE_REPO}" init -q -b main
  git -C "${LILBEE_REPO}" add .gitignore packaging tools
  commit "first"
  git -C "${LILBEE_REPO}" tag pin-9
  COMMIT="$(git -C "${LILBEE_REPO}" rev-parse HEAD)"
  unset LILBEE_DIR LILBEE_DEV RUNNER_OS PLATFORM BACKEND RUST_FEATURES RUNNER TIMEOUT OUT_DIR
}

commit() {
  git -C "${LILBEE_REPO}" -c user.name=t -c user.email=t@example.test -c commit.gpgsign=false commit -q -m "$1" --allow-empty
}

# A checkout of the stand-in at the tag, for LILBEE_DIR.
checkout() {
  git clone -q --branch pin-9 "${LILBEE_REPO}" "${BATS_TEST_TMPDIR}/tree" 2>&1
  export LILBEE_DIR="${BATS_TEST_TMPDIR}/tree"
}

value() {  # key
  sed -n "s/^$1=//p" "${OUT_DIR:-${PACKS}/dist/mistralrs-linux}/env.txt"
}

@test "a cell is built in a new clone of the tag into dist/<id>" {
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [[ "$(cat "${PACKS}/dist/mistralrs-linux/pwd.txt")" == "${PACKS}/.work/lilbee-${COMMIT}."* ]]
  [ "$(git -C "${PACKS}"/.work/lilbee-* rev-parse HEAD)" = "${COMMIT}" ]
}

@test "two builds use two clones" {
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  mv "${PACKS}/dist" "${PACKS}/kept"
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  local trees=("${PACKS}"/.work/lilbee-*)
  [ "${#trees[@]}" -eq 2 ]
}

@test "the recipe receives the cell, the pins and the image" {
  RUST_FEATURES=leaked run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [ "$(value BACKEND)" = cpu ]
  [ "$(value PLATFORM)" = manylinux_2_35_x86_64 ]
  [ "$(value RUST_TARGET)" = t ]
  [ "$(value MISTRALRS_TAG)" = v0.9.5 ]
  [ "$(value MACOSX_DEPLOYMENT_TARGET)" = 14.0 ]
  [ "$(value MANYLINUX_IMAGE)" = quay.io/pypa/x@sha256:abc ]
  [ "$(value OUT)" = "${PACKS}/dist/mistralrs-linux" ]
}

@test "a key that only another cell has is empty, not a value of this computer" {
  RUST_FEATURES=leaked run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  grep -qx 'RUST_FEATURES=' "${PACKS}/dist/mistralrs-linux/env.txt"
}

@test "the runner and the timeout are not passed" {
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  run grep -E '^(RUNNER|TIMEOUT)=' "${PACKS}/dist/mistralrs-linux/env.txt"
  [ "$status" -eq 1 ]
}

@test "cc becomes CUDA_CC and neither CC nor OS is set" {
  CC=keep OS=keep run bash "${SCRIPT}" tei-linux
  [ "$status" -eq 0 ]
  OUT_DIR="${PACKS}/dist/tei-linux"
  [ "$(value CUDA_CC)" = 80 ]
  [ "$(value CC)" = keep ]
  [ "$(value OS)" = keep ]
}

@test "a pin holds where no cell has its key" {
  run bash "${SCRIPT}" ik-linux-cpu
  [ "$status" -eq 0 ]
  OUT_DIR="${PACKS}/dist/ik-linux-cpu"
  [ "$(value PLATFORM)" = manylinux_2_34_x86_64 ]
  [ "$(value BUILD_NUMBER)" = 4 ]
}

@test "the recipe runs with umask 022 whatever the shell has" {
  umask 0077
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [ "$(cat "${PACKS}/dist/mistralrs-linux/umask.txt")" = 0022 ]
  [ "$(find "${PACKS}"/.work/lilbee-*/packaging/project -perm 644 | wc -l)" -eq 1 ]
}

@test "the sha256 of each file is printed" {
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9a-f]{64}\ [\ *]pwd\.txt ]]
}

@test "LILBEE_DIR at the commit of the tag is the tree" {
  checkout
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [ "$(cat "${PACKS}/dist/mistralrs-linux/pwd.txt")" = "${LILBEE_DIR}" ]
  [ ! -e "${PACKS}/.work" ]
}

@test "a relative LILBEE_DIR works, as the job passes it" {
  checkout
  cd "${BATS_TEST_TMPDIR}"
  LILBEE_DIR=tree run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
}

@test "LILBEE_DIR at another commit is refused" {
  commit "second"
  git clone -q "${LILBEE_REPO}" "${BATS_TEST_TMPDIR}/tree"
  LILBEE_DIR="${BATS_TEST_TMPDIR}/tree" run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not at commit ${COMMIT} of the lilbee tag pin-9"* ]]
  [ ! -e "${PACKS}/dist/mistralrs-linux" ]
}

@test "LILBEE_DIR with an edited file is refused" {
  checkout
  echo changed > "${LILBEE_DIR}/packaging/project"
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"packaging/project"* ]]
}

@test "LILBEE_DIR with an ignored file in packaging is refused" {
  checkout
  mkdir "${LILBEE_DIR}/packaging/dist"
  echo old > "${LILBEE_DIR}/packaging/dist/old.whl"
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"packaging/dist/"* ]]
}

@test "LILBEE_DEV builds the tree as it is into dist-dev" {
  checkout
  echo changed > "${LILBEE_DIR}/packaging/project"
  LILBEE_DEV=1 run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 0 ]
  [ -e "${PACKS}/dist-dev/mistralrs-linux/env.txt" ]
  [ ! -e "${PACKS}/dist" ]
}

@test "LILBEE_DEV without LILBEE_DIR is refused" {
  LILBEE_DEV=1 run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs LILBEE_DIR"* ]]
}

@test "a cell of another system exits 2 and names the workflow command" {
  STUB_UNAME_S=Darwin STUB_UNAME_M=arm64 run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs Linux x86_64; this computer is macOS arm64"* ]]
  [[ "$output" == *"gh workflow run build-packs.yml -f engine=mistralrs -f publish=false"* ]]
  run bash "${SCRIPT}" mistralrs-win
  [ "$status" -eq 2 ]
  [ ! -e "${PACKS}/dist" ]
}

@test "a cell of another machine exits 2" {
  STUB_UNAME_M=aarch64 run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 2 ]
  STUB_UNAME_S=Darwin run bash "${SCRIPT}" mistralrs-mac
  [ "$status" -eq 2 ]
}

@test "the macOS and Windows cells run on their hosts" {
  STUB_UNAME_S=Darwin STUB_UNAME_M=arm64 run bash "${SCRIPT}" mistralrs-mac
  [ "$status" -eq 0 ]
  grep -qx 'RUST_FEATURES=metal' "${PACKS}/dist/mistralrs-mac/env.txt"
  STUB_UNAME_S=MINGW64_NT-10.0-20348 run bash "${SCRIPT}" mistralrs-win
  [ "$status" -eq 0 ]
}

@test "an unknown id fails" {
  run bash "${SCRIPT}" mistralrs-nothing
  [ "$status" -eq 1 ]
  [[ "$output" == *"has the id 'mistralrs-nothing'"* ]]
}

@test "a missing id fails" {
  run bash "${SCRIPT}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: pack.sh"* ]]
}

@test "a cell name of two engines fails and names the ids" {
  run bash "${SCRIPT}" linux-cpu
  [ "$status" -eq 1 ]
  [[ "$output" == *"Use one of: llama-linux-cpu, ik-linux-cpu."* ]]
}

@test "an engine whose recipe the tag does not hold fails" {
  run bash "${SCRIPT}" llama-linux-cpu
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no tools/wheel-build/pack_llama.sh"* ]]
}

@test "a recipe that fails fails the command" {
  echo fail > "${LILBEE_REPO}/fail"
  git -C "${LILBEE_REPO}" add fail
  commit "fail"
  git -C "${LILBEE_REPO}" tag -f pin-9
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -ne 0 ]
}

@test "an output folder with files of an earlier build is refused" {
  mkdir -p "${PACKS}/dist/mistralrs-linux"
  echo old > "${PACKS}/dist/mistralrs-linux/old.whl"
  run bash "${SCRIPT}" mistralrs-linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"holds files of an earlier build"* ]]
}

@test "every cell of cells.yml has one id" {
  cp "${REPO_ROOT}/cells.yml" "${PACKS}/cells.yml"
  local engine cell ids=0
  while read -r engine cell; do
    case "${cell}" in "${engine}"-*) ;; *) cell="${engine}-${cell}" ;; esac
    STUB_UNAME_S=Plan9 run bash "${SCRIPT}" "${cell}"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cell ${cell} needs "* ]]
    ids=$((ids + 1))
  done < <(yq -r '.engines | @json' "${PACKS}/cells.yml" | jq -r 'to_entries[] | .key as $e | .value.cells[] | "\($e) \(.cell)"')
  [ "${ids}" -gt 0 ]
}

@test "the Metal cell of mistral.rs has the tag of macOS 15.0" {
  [ "$(yq -r '.engines.mistralrs.cells[] | select(.backend == "metal") | .cell + " " + .platform' "${REPO_ROOT}/cells.yml")" = "mistralrs-macos-arm64-metal macosx_15_0_arm64" ]
}

# The wheel check reads the target of the Metal libraries only. It cannot see a class that an older macOS lacks.
@test "the tag of the Metal cell of mistral.rs is macOS 15 or later, because candle makes a residency set" {
  major="$(yq -r '.engines.mistralrs.cells[] | select(.backend == "metal") | .platform' "${REPO_ROOT}/cells.yml" | sed -n 's/^macosx_\([0-9][0-9]*\)_[0-9][0-9]*_arm64$/\1/p')"
  [ "${major}" -ge 15 ]
}

@test "the Metal cell of mistral.rs passes its platform to the recipe on the Mac" {
  cp "${REPO_ROOT}/cells.yml" "${PACKS}/cells.yml"
  STUB_UNAME_S=Darwin STUB_UNAME_M=arm64 run bash "${SCRIPT}" mistralrs-macos-arm64-metal
  [ "$status" -eq 0 ]
  OUT_DIR="${PACKS}/dist/mistralrs-macos-arm64-metal"
  [ "$(value PLATFORM)" = macosx_15_0_arm64 ]
  [ "$(value BACKEND)" = metal ]
}

@test "the mistralrs job is the checkouts, the tools and one pack step" {
  local job='.jobs.mistralrs' workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq -r "[${job}.steps[] | .uses // .name] | @json" "${workflow}")" = '["actions/checkout@v7","actions/checkout@v7","actions/setup-python@v7","Install the pinned yq","Build and check the pack","actions/upload-artifact@v7"]' ]
  [ "$(yq -r "${job}.steps[] | select(.name == \"Build and check the pack\") | .run" "${workflow}")" = 'bash scripts/pack.sh "${CELL}"' ]
  [ "$(yq -r "${job}.env.CELL" "${workflow}")" = '${{ matrix.cell }}' ]
  [ "$(yq -r "${job}.env.LILBEE_DIR" "${workflow}")" = "$(yq -r "${job}.steps[1].with.path" "${workflow}")" ]
  [ "$(yq -r "${job}.steps[1].with.ref" "${workflow}")" = '${{ needs.plan.outputs.lilbee_ref }}' ]
  [ "$(yq -r "${job}.steps[-1].with.name" "${workflow}")" = 'engine-pack-${{ matrix.cell }}' ]
  [ "$(yq -r "${job}.steps[-1].with.path" "${workflow}")" = 'dist/${{ matrix.cell }}/*' ]
}

@test "a step of the mistralrs job that fails fails the job" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq '.jobs.mistralrs | .. | select(tag == "!!map") | has("continue-on-error")' "${workflow}" | sort -u)" = false ]
  [ "$(yq -r '.jobs.mistralrs.defaults.run.shell' "${workflow}")" = bash ]
  [ "$(yq '[.jobs.mistralrs.steps[] | select(has("shell"))] | length' "${workflow}")" -eq 0 ]
}

@test "only the yq step of the mistralrs job has a condition, and it runs on Windows" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq -r '.jobs.mistralrs.steps[] | select(has("if")) | .name + ": " + .if' "${workflow}")" = "Install the pinned yq: runner.os == 'Windows'" ]
  [ "$(yq -r '.jobs.mistralrs.steps[] | select(.name == "Install the pinned yq") | .run' "${workflow}")" = 'bash scripts/install_yq.sh "${RUNNER_TEMP}/bin"
echo "${RUNNER_TEMP}/bin" >> "$GITHUB_PATH"' ]
}

@test "the tei job is the checkouts, Python, the steps of a runner and one pack step" {
  local job='.jobs.tei' workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq -r "[${job}.steps[] | .uses // .name] | @json" "${workflow}")" = '["actions/checkout@v7","actions/checkout@v7","actions/setup-python@v7","Free disk space for the CUDA build","Install the CPU emulator","Build and check the pack","actions/upload-artifact@v7"]' ]
  [ "$(yq -r "${job}.steps[] | select(.name == \"Build and check the pack\") | .run" "${workflow}")" = 'bash scripts/pack.sh "${CELL}"' ]
  [ "$(yq -r "[${job}.steps[] | select(.if) | .if] | @json" "${workflow}")" = "[\"matrix.cc != ''\",\"matrix.os == 'linux'\"]" ]
  [[ "$(yq -r "${job}.steps[] | select(.name == \"Install the CPU emulator\") | .run" "${workflow}")" == *"apt-get install -y qemu-user-static"* ]]
  [ "$(yq -r "${job}.env.CELL" "${workflow}")" = '${{ matrix.cell }}' ]
  [ "$(yq -r "${job}.env.LILBEE_DIR" "${workflow}")" = "$(yq -r "${job}.steps[1].with.path" "${workflow}")" ]
  [ "$(yq -r "${job}.steps[1].with.ref" "${workflow}")" = '${{ needs.plan.outputs.lilbee_ref }}' ]
  [ "$(yq -r "${job}.steps[-1].with.name" "${workflow}")" = 'tei-pack-${{ matrix.cell }}' ]
  [ "$(yq -r "${job}.steps[-1].with.path" "${workflow}")" = 'dist/${{ matrix.cell }}/*' ]
}

@test "a step of the tei job that fails fails the job" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq '.jobs.tei | .. | select(tag == "!!map") | has("continue-on-error")' "${workflow}" | sort -u)" = false ]
  [ "$(yq -r '.jobs.tei.defaults.run.shell' "${workflow}")" = bash ]
  [ "$(yq '[.jobs.tei.steps[] | select(has("shell"))] | length' "${workflow}")" -eq 0 ]
}

@test "the output folder of each mistralrs and tei cell is the folder that the job uploads" {
  local engine cell cells
  for engine in mistralrs tei; do
    cells="$(yq -r ".engines.${engine}.cells[].cell" "${REPO_ROOT}/cells.yml")"
    [ -n "${cells}" ]
    while read -r cell; do
      STUB_UNAME_S=Plan9 run bash "${SCRIPT}" "${cell}" "${REPO_ROOT}/cells.yml"
      [[ "$output" == *"cell ${cell} needs "* ]]
    done <<< "${cells}"
  done
}

@test "the ik job is the checkouts, the disk step, Python and one pack step" {
  local job='.jobs.ik' workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq -r "[${job}.steps[] | .uses // .name] | @json" "${workflow}")" = '["actions/checkout@v7","actions/checkout@v7","Free disk space for the build","actions/setup-python@v7","Build and check the pack","actions/upload-artifact@v7"]' ]
  [ "$(yq -r "${job}.steps[] | select(.name == \"Build and check the pack\") | .run" "${workflow}")" = 'bash scripts/pack.sh "${CELL}"' ]
  [[ "$(yq -r "${job}.steps[] | select(.name == \"Free disk space for the build\") | .run" "${workflow}")" == *"sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/lib/android /opt/hostedtoolcache
"* ]]
  [ "$(yq -r "${job}.env.CELL" "${workflow}")" = 'ik-${{ matrix.cell }}' ]
  # Two missing keys are equal, so each side has its own line.
  [ "$(yq -r "${job}.env.LILBEE_DIR" "${workflow}")" = lilbee ]
  [ "$(yq -r "${job}.steps[1].with.path" "${workflow}")" = lilbee ]
  [ "$(yq -r "${job}.steps[1].with.ref" "${workflow}")" = '${{ needs.plan.outputs.lilbee_ref }}' ]
  [ "$(yq -r "${job}.steps[-1].with.name" "${workflow}")" = 'ik-pack-${{ matrix.cell }}' ]
  [ "$(yq -r "${job}.steps[-1].with.path" "${workflow}")" = 'dist/ik-${{ matrix.cell }}/*' ]
}

@test "a step of the ik job that fails fails the job, and no step has a condition" {
  local workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq '.jobs.ik | .. | select(tag == "!!map") | has("continue-on-error")' "${workflow}" | sort -u)" = false ]
  [ "$(yq -r '.jobs.ik.defaults.run.shell' "${workflow}")" = bash ]
  [ "$(yq '[.jobs.ik.steps[] | select(has("shell"))] | length' "${workflow}")" -eq 0 ]
  [ "$(yq '[.jobs.ik.steps[] | select(has("if"))] | length' "${workflow}")" -eq 0 ]
}

@test "the output folder of each ik cell is the folder that the job uploads" {
  local cell cells
  cells="$(yq -r '.engines.ik.cells[].cell' "${REPO_ROOT}/cells.yml")"
  [ -n "${cells}" ]
  while read -r cell; do
    STUB_UNAME_S=Plan9 run bash "${SCRIPT}" "ik-${cell}" "${REPO_ROOT}/cells.yml"
    [[ "$output" == *"cell ik-${cell} needs "* ]]
  done <<< "${cells}"
}

@test "the ik recipe receives its own pins and the values of its cell" {
  UPSTREAM_REPO=ggml-org/llama.cpp run bash "${SCRIPT}" ik-linux-x86_64-cuda "${REPO_ROOT}/cells.yml"
  [ "$status" -eq 0 ]
  OUT_DIR="${PACKS}/dist/ik-linux-x86_64-cuda"
  # Two failed calls are equal, so each expected value is read first and has its own form.
  local commit number
  commit="$(yq -r '.engines.ik.pins.UPSTREAM_COMMIT' "${REPO_ROOT}/cells.yml")"
  [[ "${commit}" =~ ^[0-9a-f]{40}$ ]]
  number="$(yq -r '.engines.ik.cells[] | select(.cell == "linux-x86_64-cuda") | .build_number' "${REPO_ROOT}/cells.yml")"
  [[ "${number}" =~ ^[0-9]+$ ]]
  [ "$(value UPSTREAM_REPO)" = ikawrakow/ik_llama.cpp ]
  [ "$(value UPSTREAM_COMMIT)" = "${commit}" ]
  [ "$(value PLATFORM)" = manylinux_2_34_x86_64 ]
  [ "$(value BACKEND)" = cuda ]
  [ "$(value BUILD_NUMBER)" = "${number}" ]
  [ "$(value LICENSE_TERMS)" = "MIT AND LicenseRef-NVIDIA-CUDA-EULA" ]
}

@test "install_yq refuses a download with another digest" {
  ln -s "${REPO_ROOT}/tests/stubs/curl" "${STUB_BIN}/curl"
  STUB_CURL_TEXT=other run bash "${REPO_ROOT}/scripts/install_yq.sh" "${BATS_TEST_TMPDIR}/yq"
  [ "$status" -ne 0 ]
}

@test "install_yq accepts the download with the pinned digest" {
  ln -s "${REPO_ROOT}/tests/stubs/curl" "${STUB_BIN}/curl"
  local digest script="${BATS_TEST_TMPDIR}/install_yq.sh"
  digest="$(printf 'yq\n' | sha256sum | cut -d' ' -f1)"
  sed "s/^sha256=.*/sha256=${digest}/" "${REPO_ROOT}/scripts/install_yq.sh" > "${script}"
  STUB_CURL_TEXT=yq run bash "${script}" "${BATS_TEST_TMPDIR}/yq"
  [ "$status" -eq 0 ]
}
