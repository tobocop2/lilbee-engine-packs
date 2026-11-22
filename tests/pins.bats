#!/usr/bin/env bats
# cells.yml holds the pins of each engine and the build image. build-packs.yml holds the same
# values in its env for each engine that does not build through scripts/pack.sh. A pin that differs
# would build one version and test another, so each pin is compared here.

load helpers

setup() {
  use_stubs
  CELLS="${REPO_ROOT}/cells.yml"
  WORKFLOW="${REPO_ROOT}/.github/workflows/build-packs.yml"
}

pin() {  # engine key
  yq -r ".engines.$1.pins.$2" "${CELLS}"
}

@test "the llama pins equal the env of the workflow" {
  local key
  for key in UPSTREAM_REPO UPSTREAM_TAG WHEEL_VERSION GO_LICENSES_VERSION MACOSX_DEPLOYMENT_TARGET; do
    [ "$(pin llama "${key}")" = "$(yq -r ".env.${key}" "${WORKFLOW}")" ]
  done
}

@test "the mistralrs pins are in cells.yml only" {
  local key
  for key in MISTRALRS_REPO MISTRALRS_TAG MISTRALRS_CHAT_MODEL CARGO_ABOUT_VERSION; do
    [[ "$(pin mistralrs "${key}")" =~ [0-9A-Za-z] ]]
    [ "$(pin mistralrs "${key}")" != null ]
    run grep -F "${key}" "${WORKFLOW}"
    [ "$status" -eq 1 ]
  done
  [ "$(pin mistralrs MACOSX_DEPLOYMENT_TARGET)" = "$(yq -r '.env.MACOSX_DEPLOYMENT_TARGET' "${WORKFLOW}")" ]
}

@test "the tei pins equal the env of the tei job" {
  local key
  for key in TEI_REPO TEI_TAG WHEEL_VERSION RUSTC_VERSION CUDA_VERSION CUDA_PACKAGE_SUFFIX; do
    [ "$(pin tei "${key}")" = "$(yq -r ".jobs.tei.env.${key}" "${WORKFLOW}")" ]
  done
}

@test "the ik pins equal the env of the ik job" {
  local key
  for key in UPSTREAM_REPO UPSTREAM_COMMIT PLATFORM; do
    [ "$(pin ik "${key}")" = "$(yq -r ".jobs.ik.env.${key}" "${WORKFLOW}")" ]
  done
}

@test "every manylinux image in the workflow is the image of cells.yml" {
  local image all same
  image="$(yq -r '.manylinux_image' "${CELLS}")"
  all="$(grep -c 'quay.io/pypa/manylinux' "${WORKFLOW}")"
  same="$(grep -cF "${image}" "${WORKFLOW}")"
  [ "${all}" -gt 0 ]
  [ "${all}" -eq "${same}" ]
}

@test "the image names a digest" {
  [[ "$(yq -r '.manylinux_image' "${CELLS}")" =~ @sha256:[0-9a-f]{64}$ ]]
}
