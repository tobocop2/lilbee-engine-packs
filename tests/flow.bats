#!/usr/bin/env bats
# The one flow for every engine in build-packs.yml: the plan is the switch of each build job, it skips the
# published wheels that scripts/published.sh lists, and lilbee's install checks gate the plan and the release.

load helpers

setup() {
  use_stubs gh
  WORKFLOW="${REPO_ROOT}/.github/workflows/build-packs.yml"
  mkdir -p "${BATS_TEST_TMPDIR}/pages"
  STUB_GH_PAGES="${BATS_TEST_TMPDIR}/pages"
  export STUB_GH_PAGES
  export GITHUB_REPOSITORY="owner/packs"
}

# page <n> <tag> <asset>...: page <n> of the release list, one release with the tag that holds the assets.
page() {
  local n="$1" tag="$2"
  shift 2
  printf '%s\n' "$@" | jq -R '{name: .}' | jq -s --arg tag "${tag}" '[{tag_name: $tag, assets: .}]' \
    > "${STUB_GH_PAGES}/${n}.json"
}

steps() {  # job
  yq -r "[.jobs.$1.steps[] | .uses // .name // .id] | join(\" | \")" "${WORKFLOW}"
}

@test "published.sh prints each asset of every page with the tag of its release" {
  page 1 engine-packs-2 a.whl b.whl
  page 2 engine-packs-1 c.whl
  run bash "${REPO_ROOT}/scripts/published.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "a.whl engine-packs-2
b.whl engine-packs-2
c.whl engine-packs-1" ]
  grep -q -- '--paginate' "${STUB_GH_LOG}"
  grep -q '^api repos/owner/packs/releases ' "${STUB_GH_LOG}"
}

@test "published.sh fails when the release list fails, so the plan never reads a short list" {
  page 1 engine-packs-2 a.whl
  page 2 engine-packs-1 c.whl
  STUB_GH_API_FAIL=after-first-page run bash "${REPO_ROOT}/scripts/published.sh"
  [ "$status" -ne 0 ]
  STUB_GH_API_FAIL=now run bash "${REPO_ROOT}/scripts/published.sh"
  [ "$status" -ne 0 ]
}

@test "published.sh refuses an empty repository name before any gh call" {
  GITHUB_REPOSITORY="" run bash "${REPO_ROOT}/scripts/published.sh"
  [ "$status" -eq 2 ]
  [ ! -s "${STUB_GH_LOG}" ]
}

@test "the output of published.sh is the published file of plan.sh" {
  page 1 engine-packs-20261119-ik \
    lilbee_engine_ik_llama_cpp-0+git13cffc006b82-4.cpu-py3-none-manylinux_2_34_x86_64.whl
  bash "${REPO_ROOT}/scripts/published.sh" > "${BATS_TEST_TMPDIR}/published.txt"
  run bash "${REPO_ROOT}/scripts/plan.sh" ik "" "${REPO_ROOT}/cells.yml" "${BATS_TEST_TMPDIR}/published.txt"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ik[].cell' <<< "${lines[-1]}")" = linux-x86_64-cuda ]
}

@test "each build job runs when the plan gives it cells, and reads its matrix from the plan" {
  local job engine
  for job in cell mistralrs tei ik mlx; do
    engine="${job}"
    [ "${job}" != cell ] || engine=llama
    [ "$(yq -r ".jobs.${job}.if" "${WORKFLOW}")" = "needs.plan.outputs.${engine} != '[]'" ]
    [ "$(yq -r ".jobs.${job}.strategy.matrix.include" "${WORKFLOW}")" = "\${{ fromJSON(needs.plan.outputs.${engine}) }}" ]
  done
}

@test "the engine input offers all and every engine of cells.yml" {
  [ "$(yq -r '.on.workflow_dispatch.inputs.engine.options | join(" ")' "${WORKFLOW}")" = "all $(yq -r '.engines | keys | join(" ")' "${REPO_ROOT}/cells.yml")" ]
}

@test "the mlx job builds the id that pack.sh gives an mlx cell and uploads its folder" {
  [ "$(yq -r '.jobs.mlx.env.CELL' "${WORKFLOW}")" = 'mlx-${{ matrix.cell }}' ]
  [ "$(yq -r '.jobs.mlx.steps[] | select(.uses == "actions/upload-artifact@v7") | .with.path' "${WORKFLOW}")" = 'dist/mlx-${{ matrix.cell }}/*' ]
  [ "$(yq -r '.jobs.mlx.steps[] | select(.uses == "actions/upload-artifact@v7") | .with.name' "${WORKFLOW}")" = 'mlx-pack-${{ matrix.cell }}' ]
}

@test "the engine input is not read past the plan step" {
  [ "$(grep -c 'inputs.engine' "${WORKFLOW}")" -eq 1 ]
  [ "$(yq -r '.jobs.plan.steps[] | select(.id == "plan") | .env.ENGINE' "${WORKFLOW}")" = '${{ inputs.engine }}' ]
}

@test "the plan lists the published wheels, plans, and then screens the licences with the lilbee tag" {
  [ "$(steps plan)" = "actions/checkout@v7 | pin | List the published wheels | plan | actions/checkout@v7 | astral-sh/setup-uv@v7 | Screen the licence of each planned cell" ]
  [ "$(yq -r '.jobs.plan.steps[] | select(.name == "List the published wheels") | .run' "${WORKFLOW}")" = 'bash scripts/published.sh > published.txt' ]
  [ "$(yq -r '.jobs.plan.env.GH_TOKEN' "${WORKFLOW}")" = '${{ github.token }}' ]
  [[ "$(yq -r '.jobs.plan.steps[] | select(.id == "plan") | .run' "${WORKFLOW}")" == *'bash scripts/plan.sh "${ENGINE}" "" cells.yml published.txt > plan.json'* ]]
  [ "$(yq -r '.jobs.plan.steps[4].with.repository' "${WORKFLOW}")" = tobocop2/lilbee ]
  [ "$(yq -r '.jobs.plan.steps[4].with.ref' "${WORKFLOW}")" = '${{ steps.pin.outputs.ref }}' ]
  [ "$(yq -r '.jobs.plan.steps[4].with.path' "${WORKFLOW}")" = lilbee ]
  [ "$(yq -r '.jobs.plan.steps[4].with."persist-credentials"' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs.plan.steps[-1].run' "${WORKFLOW}")" = 'uv run --project lilbee --locked --no-dev python lilbee/tools/check_pack_licences.py terms plan.json' ]
  [ "$(yq -r '[.jobs.plan.steps[] | select(has("if") or has("continue-on-error"))] | length' "${WORKFLOW}")" -eq 0 ]
}

@test "the plan step writes one output for each engine and says whether any cell is planned" {
  local script
  script="$(yq -r '.jobs.plan.steps[] | select(.id == "plan") | .run' "${WORKFLOW}")"
  cd "${BATS_TEST_TMPDIR}"
  mkdir scripts
  cp "${REPO_ROOT}/scripts/plan.sh" "${REPO_ROOT}/scripts/wheel_name.bash" scripts/
  cp "${REPO_ROOT}/cells.yml" cells.yml
  : > published.txt
  ENGINE=ik GITHUB_OUTPUT=out.txt run bash -c "${script}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^ik=//p' out.txt | jq length)" -eq 2 ]
  [ "$(sed -n 's/^llama=//p' out.txt)" = "[]" ]
  [ "$(sed -n 's/^any=//p' out.txt)" = true ]
  [ "$(cut -d= -f1 out.txt | tr '\n' ' ')" = "llama mistralrs tei ik mlx any " ]
  yq -r '.engines.ik.cells[] | "lilbee_engine_ik_llama_cpp-0+git13cffc006b82-\(.build_number).\(.backend)-py3-none-manylinux_2_34_x86_64.whl r"' cells.yml > published.txt
  ENGINE=ik GITHUB_OUTPUT=out2.txt run bash -c "${script}"
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^any=//p' out2.txt)" = false ]
  [ "$(sed -n 's/^ik=//p' out2.txt)" = "[]" ]
}

@test "the publish job checks each wheel with the lilbee tag after the download and before the release" {
  [ "$(steps publish)" = "actions/checkout@v7 | Require every build job to have succeeded | actions/download-artifact@v8 | actions/checkout@v7 | astral-sh/setup-uv@v7 | Check each wheel as lilbee engine install does | Create the release and upload the wheels" ]
  [ "$(yq -r '.jobs.publish.steps[3].with.repository' "${WORKFLOW}")" = tobocop2/lilbee ]
  [ "$(yq -r '.jobs.publish.steps[3].with.ref' "${WORKFLOW}")" = '${{ needs.plan.outputs.lilbee_ref }}' ]
  [ "$(yq -r '.jobs.publish.steps[3].with.path' "${WORKFLOW}")" = lilbee ]
  [ "$(yq -r '.jobs.publish.steps[] | select(.name == "Check each wheel as lilbee engine install does") | .run' "${WORKFLOW}")" = 'uv run --project lilbee --locked --no-dev python lilbee/tools/check_pack_licences.py wheels packs' ]
  [ "$(yq -r '.jobs.publish.steps[2].with.path' "${WORKFLOW}")" = packs ]
  [ "$(yq -r '[.jobs.publish.steps[] | select(has("if") or has("continue-on-error"))] | length' "${WORKFLOW}")" -eq 0 ]
}
