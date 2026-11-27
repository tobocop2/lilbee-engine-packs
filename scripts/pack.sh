#!/usr/bin/env bash
# Build and check one cell of cells.yml into dist/<id>/:
#
#   bash scripts/pack.sh <id> [cells-file]
#
# <id> is the cell name, or the engine name and the cell name joined by a dash (ik-linux-x86_64-cpu).
# The script exports the cell and the pins of its engine, gets the lilbee tree of the tag in LILBEE_REF,
# and runs tools/wheel-build/pack_<engine>.sh of that tree with OUT set to the output folder.
# It exits 2 when this computer cannot build the cell. It fails when the output folder holds another
# engine wheel than the one file that scripts/wheel_name.bash names for the cell.
#
#   LILBEE_DIR    a lilbee checkout to build in. It must be clean and at the commit of the tag.
#                 Without it, the script clones the tag into a new folder under .work/.
#   LILBEE_DEV=1  builds in LILBEE_DIR as it is, for a recipe that has no tag. The output goes to dist-dev/.
#
# The script needs git, jq, yq, and what the recipe of the engine needs. It deletes nothing.

set -euo pipefail

# The mode of each file in the checkout goes into the wheel.
umask 022

id="${1:?usage: pack.sh <id> [cells-file]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cells="${2:-${root}/cells.yml}"

fail() {  # status message
  echo "pack: $2" >&2
  exit "$1"
}

engines="$(yq -r '.engines | @json' "${cells}" | tr -d '\r')"
found="$(jq -c --arg id "${id}" '[to_entries[] | .key as $engine | .value as $value | $value.cells[]
  | select(.cell == $id or ($engine + "-" + .cell) == $id)
  | {engine: $engine, cell: ., pins: $value.pins, keys: ([$value.cells[] | keys[]] | unique),
     id: (if .cell | startswith($engine + "-") then .cell else $engine + "-" + .cell end)}]' <<< "${engines}" | tr -d '\r')"
case "$(jq 'length' <<< "${found}" | tr -d '\r')" in
  1) ;;
  0) fail 1 "no cell in ${cells} has the id '${id}'." ;;
  *) fail 1 "'${id}' names more than one cell. Use one of: $(jq -r 'map(.id) | join(", ")' <<< "${found}" | tr -d '\r')." ;;
esac
selected="$(jq -c '.[0]' <<< "${found}" | tr -d '\r')"
id="$(jq -r '.id' <<< "${selected}" | tr -d '\r')"
engine="$(jq -r '.engine' <<< "${selected}" | tr -d '\r')"
# The name that scripts/plan.sh looks up in the releases to skip a published cell. The recipe must write it.
# shellcheck source=scripts/wheel_name.bash
source "${root}/scripts/wheel_name.bash"
wheel="$(jq -r "${WHEEL_NAME_JQ}"' .pins as $pins | .cell | wheel_name($engine; $pins)' \
  --arg engine "${engine}" <<< "${selected}" | tr -d '\r')"

# A key that only other cells of the engine have is empty, as it is in a job matrix.
# CC names the C compiler and OS the operating system in many tools, so those keys keep other names.
contract="$(jq -r '
  def name: {license: "LICENSE_TERMS", cc: "CUDA_CC"}[.] // ascii_upcase;
  (.keys - ["cell", "runner", "timeout", "os"]) as $keys
  | ([$keys[] | {key: name, value: ""}] | from_entries)
    + .pins
    + ([.cell | to_entries[] | select(.key as $key | $keys | index($key)) | {key: (.key | name), value}] | from_entries)
  | to_entries[] | "\(.key)=\(.value)"' <<< "${selected}" | tr -d '\r')"
while IFS= read -r pair; do
  export "${pair%%=*}=${pair#*=}"
done <<< "${contract}"
MANYLINUX_IMAGE="$(yq -r '.manylinux_image' "${cells}" | tr -d '\r')"
export MANYLINUX_IMAGE

case "${PLATFORM:-}" in
  manylinux_*_x86_64) want="Linux x86_64" ;;
  macosx_*_arm64) want="macOS arm64" ;;
  win_amd64) want="Windows x86_64" ;;
  *) fail 1 "cell ${id} has the platform '${PLATFORM:-}', which no computer builds." ;;
esac
case "$(uname -s)" in
  Linux) host="Linux $(uname -m)" ;;
  Darwin) host="macOS $(uname -m)" ;;
  MINGW* | MSYS* | CYGWIN*) host="Windows $(uname -m)" ;;
  *) host="$(uname -s) $(uname -m)" ;;
esac
if [ "${host}" != "${want}" ]; then
  fail 2 "cell ${id} needs ${want}; this computer is ${host}. Build it on GitHub: gh workflow run build-packs.yml -f engine=${engine} -f publish=false"
fi

out="${root}/dist/${id}"
if [ "${LILBEE_DEV:-0}" = 1 ]; then
  [ -n "${LILBEE_DIR:-}" ] || fail 1 "LILBEE_DEV=1 needs LILBEE_DIR, the lilbee checkout to build in."
  tree="${LILBEE_DIR}"
  out="${root}/dist-dev/${id}"
else
  ref="$(bash "${root}/scripts/lilbee_ref.sh" "${root}/LILBEE_REF")"
  tag="$(sed -n 's/^tag=//p' <<< "${ref}")"
  commit="$(sed -n 's/^commit=//p' <<< "${ref}")"
  if [ -n "${LILBEE_DIR:-}" ]; then
    tree="${LILBEE_DIR}"
  else
    mkdir -p "${root}/.work"
    tree="$(mktemp -d "${root}/.work/lilbee-${commit}.XXXXXX")"
    git clone --quiet --depth 1 --branch "${tag}" "${LILBEE_REPO:-https://github.com/tobocop2/lilbee}" "${tree}"
  fi
  [ "$(git -C "${tree}" rev-parse HEAD)" = "${commit}" ] || fail 1 "${tree} is not at commit ${commit} of the lilbee tag ${tag}."
  changed="$(git -C "${tree}" status --porcelain && git -C "${tree}" status --porcelain --ignored -- packaging)"
  [ -z "${changed}" ] || fail 1 "${tree} has files that the lilbee tag ${tag} does not hold. Use a fresh checkout:
${changed}"
fi

recipe="tools/wheel-build/pack_${engine}.sh"
[ -f "${tree}/${recipe}" ] || fail 1 "the lilbee tree ${tree} has no ${recipe}."
if [ -d "${out}" ] && [ -n "$(ls -A "${out}")" ]; then
  fail 1 "${out} holds files of an earlier build. Move them away."
fi
mkdir -p "${out}"
(cd "${tree}" && OUT="${out}" bash "${recipe}")

shopt -s nullglob
built=("${out}"/lilbee_engine_*.whl)
shopt -u nullglob
if [ "${#built[@]}" -ne 1 ] || [ "${built[0]}" != "${out}/${wheel}" ]; then
  fail 1 "the recipe of ${id} wrote [${built[*]##*/}], and the plan names ${wheel}, so a run would not skip the cell once it is published. Correct the cell or scripts/wheel_name.bash."
fi

sha256="sha256sum"
command -v sha256sum >/dev/null || sha256="shasum -a 256"
(cd "${out}" && ${sha256} -- *)
