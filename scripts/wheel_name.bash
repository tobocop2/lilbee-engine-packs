# shellcheck shell=bash
# The jq function that gives the wheel file name of a cell. scripts/plan.sh and scripts/pack.sh source this file.
#
#   jq "${WHEEL_NAME_JQ}"' wheel_name($engine; $pins)'    with the cell as the input
#
# The name is <dist>-<version>-<build>.<backend>-py3-none-<platform>.whl, as each lilbee recipe writes it:
#   dist      the distribution of the engine, from the table below
#   version   the WHEEL_VERSION pin, else the MISTRALRS_TAG pin without the v,
#             else 0+git and the first 12 hex digits of the UPSTREAM_COMMIT pin
#   build     the build_number of the cell
#   backend   the backend of the cell, with each dash changed to an underscore
#   platform  the platform of the cell, else the PLATFORM pin of the engine
# A new engine adds its distribution to the table. pack.sh fails when a recipe writes another name,
# so the rule cannot drift from the recipes without a red build.
# The dollar signs are jq variables (SC2016), and the scripts that source the file read the value (SC2034).
# shellcheck disable=SC2016,SC2034
WHEEL_NAME_JQ='
def wheel_name($engine; $pins):
  ({llama: "lilbee_engine_llama_cpp", mistralrs: "lilbee_engine_mistral_rs",
    tei: "lilbee_engine_tei", ik: "lilbee_engine_ik_llama_cpp", mlx: "lilbee_engine_mlx"}[$engine]
    // error("the engine \($engine) has no distribution in scripts/wheel_name.bash")) as $dist
  | (if $pins.WHEEL_VERSION != null then $pins.WHEEL_VERSION | tostring
     elif $pins.MISTRALRS_TAG != null then $pins.MISTRALRS_TAG | tostring | ltrimstr("v")
     elif $pins.UPSTREAM_COMMIT != null then "0+git" + ($pins.UPSTREAM_COMMIT | tostring | .[:12])
     else error("the engine \($engine) has no WHEEL_VERSION, MISTRALRS_TAG or UPSTREAM_COMMIT pin")
     end) as $version
  | (.build_number // error("the cell \(.cell) of \($engine) has no build_number")) as $build
  | (.backend // error("the cell \(.cell) of \($engine) has no backend") | tostring | gsub("-"; "_")) as $backend
  | (.platform // $pins.PLATFORM // error("the cell \(.cell) of \($engine) has no platform")) as $platform
  | "\($dist)-\($version)-\($build).\($backend)-py3-none-\($platform).whl";
'
