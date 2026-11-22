#!/usr/bin/env bash
# Create the release of an engine-pack batch and upload its wheels.
#
#   bash scripts/publish.sh [--dry-run] <wheel-dir> <tag-suffix> <lilbee-tag> <lilbee-commit>
#
# The tag is engine-packs-<UTC date>[-<tag-suffix>]. The script refuses a tag that exists, a wheel
# directory without a lilbee_engine_*.whl file (a directory that does not exist is the same case: the
# download step makes no folder when no artifact matches), and a wheel file name that any release already ships.
# One file name holds one wheel: the record of a later release replaces the digest of an earlier one.
# Only lilbee_engine_*.whl files are uploaded, not the .sha256 or gfx files.
#
# <tag-suffix> must be present and may be empty. The other three values must not be empty.
# GITHUB_REPOSITORY (owner/name) names the repository; GH_TOKEN (contents: write) lets gh write.
# --dry-run reads the releases, prints the tag, the asset names and the notes, and makes no write call.

set -euo pipefail

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
  shift
fi

if [ "$#" -ne 4 ]; then
  echo "::error::usage: publish.sh [--dry-run] <wheel-dir> <tag-suffix> <lilbee-tag> <lilbee-commit>" >&2
  exit 2
fi
dir="$1"
suffix="$2"
lilbee_tag="$3"
lilbee_commit="$4"

refuse_empty() {
  if [ -z "$2" ]; then
    echo "::error::publish.sh: $1 is empty." >&2
    exit 2
  fi
}
refuse_empty "the wheel directory" "${dir}"
refuse_empty "the lilbee tag" "${lilbee_tag}"
refuse_empty "the lilbee commit" "${lilbee_commit}"
refuse_empty "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY:-}"

tag="engine-packs-$(date -u +%Y%m%d)${suffix:+-${suffix}}"
notes="Engine packs built from lilbee tag ${lilbee_tag} (commit ${lilbee_commit})."

if gh release view "${tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  echo "::error::The release ${tag} exists. Give the batch a new tag_suffix."
  exit 1
fi
wheels=("${dir}"/lilbee_engine_*.whl)
[ -e "${wheels[0]}" ] || { echo "::error::No engine wheel was built."; exit 1; }
# One file name holds one wheel: the record of a later release replaces the digest of an earlier one.
assets="$(gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate --jq '.[].assets[].name')"
clash=0
for wheel in "${wheels[@]}"; do
  name="$(basename "${wheel}")"
  if grep -qxF "${name}" <<< "${assets}"; then
    echo "::error::The file ${name} is already an asset of a release. Raise its build number."
    clash=1
  fi
done
[ "${clash}" -eq 0 ] || exit 1

if [ "${dry_run}" -eq 1 ]; then
  echo "dry run: no release is created"
  echo "tag: ${tag}"
  for wheel in "${wheels[@]}"; do
    echo "asset: $(basename "${wheel}")"
  done
  echo "notes: ${notes}"
  exit 0
fi

gh release create "${tag}" "${wheels[@]}" --repo "${GITHUB_REPOSITORY}" --latest=false \
  --title "${tag}" --notes "${notes}"
echo "Published ${tag}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
