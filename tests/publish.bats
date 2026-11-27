#!/usr/bin/env bats
# scripts/publish.sh: the release tag, the refusals, the upload and --dry-run. A stub gh stands for GitHub.

load helpers

WHEEL_3="lilbee_engine_ik_llama_cpp-0+gitabc-3.cpu-py3-none-manylinux_2_34_x86_64.whl"
WHEEL_4="lilbee_engine_ik_llama_cpp-0+gitabc-4.cpu-py3-none-manylinux_2_34_x86_64.whl"
OTHER="lilbee_engine_llama_cpp-1-1.cpu-py3-none-win_amd64.whl"

setup() {
  use_stubs gh
  SCRIPT="${REPO_ROOT}/scripts/publish.sh"
  DIR="${BATS_TEST_TMPDIR}/packs"
  mkdir -p "${DIR}" "${BATS_TEST_TMPDIR}/pages"
  STUB_GH_PAGES="${BATS_TEST_TMPDIR}/pages"
  export STUB_GH_PAGES
  export GITHUB_REPOSITORY="owner/packs"
  export GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary.md"
  TODAY="$(date -u +%Y%m%d)"
  page 1
}

# wheel <name>...: put empty wheel files in the pack folder.
wheel() {
  local name
  for name in "$@"; do : > "${DIR}/${name}"; done
}

# page <n> <asset>...: write page <n> of the release list, one release that holds the assets.
page() {
  local n="$1"
  shift
  local assets="[]"
  if [ "$#" -gt 0 ]; then
    assets="$(printf '%s\n' "$@" | jq -R '{name: .}' | jq -s .)"
  fi
  jq -n --argjson assets "${assets}" '[{tag_name: "engine-packs-1", assets: $assets}]' \
    > "${STUB_GH_PAGES}/${n}.json"
}

created() { grep -c '^release create' "${STUB_GH_LOG}" || true; }

@test "the release gets the dated tag, the wheels, --latest=false and the notes with the lilbee tag and commit" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  grep -qxF "release create engine-packs-${TODAY} ${DIR}/${WHEEL_4} --repo owner/packs --latest=false --title engine-packs-${TODAY} --notes Engine packs built from lilbee tag pin-3 (commit abc123)." "${STUB_GH_LOG}"
}

@test "PRERELEASE=true makes one create call with --prerelease and --latest=false" {
  export STUB_GH_ALLOW_WRITE=1
  export PRERELEASE=true
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  [ "$(created)" -eq 1 ]
  line="$(grep '^release create' "${STUB_GH_LOG}")"
  [[ "${line}" == *" --prerelease "* ]]
  [[ "${line}" == *" --latest=false "* ]]
}

@test "PRERELEASE=false or unset leaves --prerelease out" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  PRERELEASE=false run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  unset PRERELEASE
  run bash "${SCRIPT}" "${DIR}" llama pin-3 abc123
  [ "$status" -eq 0 ]
  [ "$(created)" -eq 2 ]
  ! grep -q -- '--prerelease' "${STUB_GH_LOG}"
  [ "$(grep -c -- '--latest=false' "${STUB_GH_LOG}")" -eq 2 ]
}

@test "the workflow has a prerelease input that defaults to false and the publish job passes it as PRERELEASE" {
  workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq '.on.workflow_dispatch.inputs.prerelease.type' "${workflow}")" = "boolean" ]
  [ "$(yq '.on.workflow_dispatch.inputs.prerelease.default' "${workflow}")" = "false" ]
  [ "$(yq '.jobs.publish.env.PRERELEASE' "${workflow}")" = '${{ inputs.prerelease }}' ]
}

@test "a tag suffix is appended to the tag" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" llama pin-3 abc123
  [ "$status" -eq 0 ]
  grep -q "^release create engine-packs-${TODAY}-llama " "${STUB_GH_LOG}"
}

@test "only lilbee_engine wheels are uploaded, not the sha256 or gfx files" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}" "${OTHER}" "${WHEEL_4}.sha256" lilbee-linux-x86_64-rocm.gfx.txt other-1-1-py3-none-any.whl
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  line="$(grep '^release create' "${STUB_GH_LOG}")"
  [[ "${line}" == *"${DIR}/${WHEEL_4}"* ]]
  [[ "${line}" == *"${DIR}/${OTHER}"* ]]
  [[ "${line}" != *sha256* ]]
  [[ "${line}" != *gfx* ]]
  [[ "${line}" != *other-1-1* ]]
}

@test "the release is published with the summary line" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  [ "$(cat "${GITHUB_STEP_SUMMARY}")" = "Published engine-packs-${TODAY}" ]
}

@test "a tag that exists is refused before any release list call and any create" {
  wheel "${WHEEL_4}"
  export STUB_GH_TAG_EXISTS=1
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::The release engine-packs-${TODAY} exists. Give the batch a new tag_suffix."* ]]
  [ "$(created)" -eq 0 ]
  [ "$(grep -c '^api' "${STUB_GH_LOG}" || true)" -eq 0 ]
}

@test "a folder without an engine wheel is refused" {
  wheel "${WHEEL_4}.sha256" other-1-1-py3-none-any.whl
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::No engine wheel was built."* ]]
  [ "$(created)" -eq 0 ]
}

@test "a wheel name that a release ships is refused, and the other wheel is not named" {
  wheel "${WHEEL_3}" "${WHEEL_4}"
  page 1 "${OTHER}" "${WHEEL_3}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::The file ${WHEEL_3} is already an asset of a release. Raise its build number."* ]]
  [[ "$output" != *"The file ${WHEEL_4} "* ]]
  [ "$(created)" -eq 0 ]
}

@test "a clashing name is refused whichever wheel comes first" {
  wheel "${WHEEL_4}" "${WHEEL_3}"
  page 1 "${WHEEL_3}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [ "$(grep -c 'is already an asset of a release' <<< "$output")" -eq 1 ]
  [ "$(created)" -eq 0 ]
}

@test "every clashing wheel is named" {
  wheel "${WHEEL_3}" "${WHEEL_4}"
  page 1 "${WHEEL_3}" "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [ "$(grep -c 'is already an asset of a release' <<< "$output")" -eq 2 ]
}

@test "a name held by a release on a later page is refused" {
  wheel "${WHEEL_4}" "${WHEEL_3}"
  page 1 "${OTHER}"
  page 2 "${OTHER}"
  page 3 "${WHEEL_3}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"The file ${WHEEL_3} is already an asset"* ]]
  [ "$(created)" -eq 0 ]
}

@test "the release list is read with every page" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  grep -q '^api repos/owner/packs/releases --paginate' "${STUB_GH_LOG}"
}

@test "a name that only contains an asset name is not a clash" {
  export STUB_GH_ALLOW_WRITE=1
  wheel "${WHEEL_4}"
  page 1 "old-${WHEEL_4}" "${WHEEL_4}.sha256"
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 0 ]
  [ "$(created)" -eq 1 ]
}

@test "a failed release list stops the script before any create" {
  wheel "${WHEEL_4}"
  for fail in now after-first-page; do
    export STUB_GH_API_FAIL="${fail}"
    run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTP 502"* ]]
  done
  [ "$(created)" -eq 0 ]
}

@test "an empty value is refused before any gh call" {
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "" "" pin-3 abc123
  [ "$status" -eq 2 ]
  [[ "$output" == *"the wheel directory is empty"* ]]
  run bash "${SCRIPT}" "${DIR}" "" "" abc123
  [ "$status" -eq 2 ]
  [[ "$output" == *"the lilbee tag is empty"* ]]
  run bash "${SCRIPT}" "${DIR}" "" pin-3 ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"the lilbee commit is empty"* ]]
  GITHUB_REPOSITORY="" run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 2 ]
  [[ "$output" == *"GITHUB_REPOSITORY is empty"* ]]
  [ ! -s "${STUB_GH_LOG}" ]
}

@test "a missing value is refused before any gh call" {
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" "${DIR}" "" pin-3
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 2 ]
  unset GITHUB_REPOSITORY
  run bash "${SCRIPT}" "${DIR}" "" pin-3 abc123
  [ "$status" -eq 2 ]
  export GITHUB_REPOSITORY=owner/packs
  [ ! -s "${STUB_GH_LOG}" ]
}

@test "a wheel folder that does not exist is the no-wheel refusal: the download step makes no folder when no artifact matches" {
  run bash "${SCRIPT}" "${BATS_TEST_TMPDIR}/none" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::No engine wheel was built."* ]]
  [ "$(created)" -eq 0 ]
}

@test "a dry run prints the tag, the asset names and the notes, and makes no write call" {
  wheel "${WHEEL_4}" "${OTHER}" "${WHEEL_4}.sha256"
  run bash "${SCRIPT}" --dry-run "${DIR}" llama pin-3 abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"tag: engine-packs-${TODAY}-llama"* ]]
  [[ "$output" == *"asset: ${WHEEL_4}"* ]]
  [[ "$output" == *"asset: ${OTHER}"* ]]
  [[ "$output" != *"sha256"* ]]
  [[ "$output" == *"notes: Engine packs built from lilbee tag pin-3 (commit abc123)."* ]]
  [ "$(created)" -eq 0 ]
  [ ! -e "${GITHUB_STEP_SUMMARY}" ]
}

@test "the stub fails every write call unless the test allows writes" {
  run gh release create engine-packs-x
  [ "$status" -eq 99 ]
  run gh release delete engine-packs-x
  [ "$status" -eq 99 ]
  local form
  for form in "-X POST" "-XPOST" "--method POST" "--method=POST" "-f name=x" "-F name=x" "--field name=x" "--field=name=x" "--raw-field name=x" "--input x.json"; do
    # shellcheck disable=SC2086
    run gh api repos/owner/packs/releases ${form}
    [ "$status" -eq 99 ]
  done
  run gh api repos/owner/packs/releases --paginate --jq '.[].assets[].name'
  [ "$status" -eq 0 ]
  STUB_GH_ALLOW_WRITE=1 run gh release create engine-packs-x
  [ "$status" -eq 0 ]
  STUB_GH_ALLOW_WRITE=1 run gh api repos/owner/packs/releases --method=POST
  [ "$status" -eq 0 ]
}

@test "a dry run refuses a tag that exists, an empty folder and a name clash" {
  wheel "${WHEEL_3}"
  STUB_GH_TAG_EXISTS=1 run bash "${SCRIPT}" --dry-run "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" != *"tag: "* ]]
  page 1 "${WHEEL_3}"
  run bash "${SCRIPT}" --dry-run "${DIR}" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"is already an asset of a release"* ]]
  [[ "$output" != *"tag: "* ]]
  page 1
  mkdir "${BATS_TEST_TMPDIR}/sums"
  : > "${BATS_TEST_TMPDIR}/sums/${WHEEL_3}.sha256"
  run bash "${SCRIPT}" --dry-run "${BATS_TEST_TMPDIR}/sums" "" pin-3 abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"No engine wheel was built."* ]]
}

@test "a dry run refuses an empty value" {
  wheel "${WHEEL_4}"
  run bash "${SCRIPT}" --dry-run "${DIR}" "" "" abc123
  [ "$status" -eq 2 ]
  [ ! -s "${STUB_GH_LOG}" ]
}

@test "the publish job checks out both repositories without a stored token, passes the suffix and calls the script in one line" {
  workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq -o=json -I=0 '[.jobs.publish.steps[] | select(.uses == "actions/checkout@v7") | .with."persist-credentials"]' "${workflow}")" = "[false,false]" ]
  [ "$(yq '.jobs.publish.env.SUFFIX' "${workflow}")" = '${{ inputs.tag_suffix }}' ]
  [ "$(yq '.jobs.publish.steps[] | select(.name == "Create the release and upload the wheels") | .run' "${workflow}")" = 'bash scripts/publish.sh packs "${SUFFIX}" "${LILBEE_TAG}" "${LILBEE_COMMIT}"' ]
  [ "$(yq '.jobs.publish.steps[] | select(.name == "Create the release and upload the wheels") | .env.LILBEE_TAG' "${workflow}")" = '${{ needs.plan.outputs.lilbee_tag }}' ]
  [ "$(yq '.jobs.publish.steps[] | select(.name == "Create the release and upload the wheels") | .env.LILBEE_COMMIT' "${workflow}")" = '${{ needs.plan.outputs.lilbee_commit }}' ]
}

@test "the publish job runs the script in one step and keeps its condition, needs, permissions and download pattern" {
  workflow="${REPO_ROOT}/.github/workflows/build-packs.yml"
  [ "$(yq '.jobs.publish.steps[] | select(.name == "Create the release and upload the wheels") | .run' "${workflow}")" = 'bash scripts/publish.sh packs "${SUFFIX}" "${LILBEE_TAG}" "${LILBEE_COMMIT}"' ]
  [ "$(yq '.jobs.publish.if' "${workflow}")" = "\${{ inputs.publish && !cancelled() && needs.plan.outputs.any == 'true' }}" ]
  [ "$(yq -o=json -I=0 '.jobs.publish.needs' "${workflow}")" = '["plan","cell","mistralrs","tei","ik"]' ]
  [ "$(yq '.jobs.publish.permissions.contents' "${workflow}")" = "write" ]
  [ "$(yq '.jobs.publish.steps[] | select(.uses == "actions/download-artifact@v8") | .with.pattern' "${workflow}")" = "*-pack-*" ]
  [ "$(yq '.jobs.publish.env.GH_TOKEN' "${workflow}")" = '${{ github.token }}' ]
}
