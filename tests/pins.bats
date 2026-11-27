#!/usr/bin/env bats
# cells.yml holds the pins of each engine and the build image, and no other file does. A second copy that differs
# would build one version and test another.

load helpers

setup() {
  use_stubs
  CELLS="${REPO_ROOT}/cells.yml"
  WORKFLOW="${REPO_ROOT}/.github/workflows/build-packs.yml"
}

pin() {  # engine key
  yq -r ".engines.$1.pins.$2" "${CELLS}"
}

@test "the llama pins are in cells.yml only" {
  local key
  for key in UPSTREAM_REPO UPSTREAM_TAG WHEEL_VERSION GO_LICENSES_VERSION MACOSX_DEPLOYMENT_TARGET; do
    [[ "$(pin llama "${key}")" =~ [0-9A-Za-z] ]]
    [ "$(pin llama "${key}")" != null ]
    run grep -F "${key}" "${WORKFLOW}"
    [ "$status" -eq 1 ]
  done
  [ "$(yq -r 'has("env")' "${WORKFLOW}")" = false ]
  [ "$(yq -r '.jobs.cell.env | keys | @json' "${WORKFLOW}")" = '["GH_TOKEN","LILBEE_DIR","CELL"]' ]
}

@test "the mistralrs pins are in cells.yml only" {
  local key
  for key in MISTRALRS_REPO MISTRALRS_TAG MISTRALRS_CHAT_MODEL CARGO_ABOUT_VERSION; do
    [[ "$(pin mistralrs "${key}")" =~ [0-9A-Za-z] ]]
    [ "$(pin mistralrs "${key}")" != null ]
    run grep -F "${key}" "${WORKFLOW}"
    [ "$status" -eq 1 ]
  done
  [ "$(pin mistralrs MACOSX_DEPLOYMENT_TARGET)" = "$(pin llama MACOSX_DEPLOYMENT_TARGET)" ]
}

@test "the tei pins are in cells.yml only" {
  local key
  for key in TEI_REPO TEI_TAG RUSTC_VERSION CUDA_VERSION CUDA_PACKAGE_SUFFIX; do
    [[ "$(pin tei "${key}")" =~ [0-9A-Za-z] ]]
    [ "$(pin tei "${key}")" != null ]
    run grep -F "${key}" "${WORKFLOW}"
    [ "$status" -eq 1 ]
  done
  [ "v$(pin tei WHEEL_VERSION)" = "$(pin tei TEI_TAG)" ]
  [ "$(yq -r '.jobs.tei.env | keys | @json' "${WORKFLOW}")" = '["LILBEE_DIR","CELL"]' ]
  [ "$(pin tei MACOSX_DEPLOYMENT_TARGET)" = "$(pin llama MACOSX_DEPLOYMENT_TARGET)" ]
}

@test "the ik pins are in cells.yml only" {
  local key
  for key in UPSTREAM_REPO UPSTREAM_COMMIT PLATFORM; do
    [[ "$(pin ik "${key}")" =~ [0-9A-Za-z] ]]
    [ "$(pin ik "${key}")" != null ]
  done
  [[ "$(pin ik UPSTREAM_COMMIT)" =~ ^[0-9a-f]{40}$ ]]
  for key in "$(pin ik UPSTREAM_REPO)" "$(pin ik UPSTREAM_COMMIT)" UPSTREAM_COMMIT; do
    run grep -F "${key}" "${WORKFLOW}"
    [ "$status" -eq 1 ]
  done
  [ "$(yq -r '.jobs.ik.env | keys | @json' "${WORKFLOW}")" = '["LILBEE_DIR","CELL"]' ]
}

@test "the mlx pin is in cells.yml only, and the one mlx cell is the macOS 14 Metal cell" {
  [[ "$(pin mlx WHEEL_VERSION)" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  run grep -F "$(pin mlx WHEEL_VERSION)" "${WORKFLOW}"
  [ "$status" -eq 1 ]
  [ "$(yq -r '.jobs.mlx.env | keys | @json' "${WORKFLOW}")" = '["LILBEE_DIR","CELL"]' ]
  [ "$(yq -r '.engines.mlx.cells | length' "${CELLS}")" -eq 1 ]
  [ "$(yq -r '.engines.mlx.cells[0] | [.backend, .platform, .runner] | join(" ")' "${CELLS}")" = "metal macosx_14_0_arm64 macos-15" ]
}

@test "the workflow names no image, so every cell builds in the image of cells.yml" {
  run grep -F 'quay.io/' "${WORKFLOW}"
  [ "$status" -eq 1 ]
}

@test "the image names a digest" {
  [[ "$(yq -r '.manylinux_image' "${CELLS}")" =~ @sha256:[0-9a-f]{64}$ ]]
}
