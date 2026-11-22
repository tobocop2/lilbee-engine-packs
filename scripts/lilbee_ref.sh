#!/usr/bin/env bash
# Print the lilbee tag that LILBEE_REF names, as lines for $GITHUB_OUTPUT:
#
#   bash scripts/lilbee_ref.sh [ref-file]
#
#   ref=refs/tags/<tag>
#   tag=<tag>
#   commit=<40-hex commit of the tag>
#
# The file holds one tag name. The script fails when the name is not a tag name,
# when the tag does not exist, or when it does not resolve to a commit.
# An annotated tag lists its commit on the line that ends in ^{}; a lightweight
# tag lists the commit on its own line.
# LILBEE_REPO names the repository to ask; the default is the public one.

set -euo pipefail

file="${1:-LILBEE_REF}"
repo="${LILBEE_REPO:-https://github.com/tobocop2/lilbee}"

ref="$(tr -d '[:space:]' < "${file}")"
if ! [[ "${ref}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "lilbee_ref: ${file} must hold one lilbee tag name" >&2
  exit 1
fi

if ! lines="$(git ls-remote --exit-code --tags "${repo}" "refs/tags/${ref}" "refs/tags/${ref}^{}")"; then
  echo "lilbee_ref: the lilbee tag ${ref} named in ${file} does not exist. Create the tag on the lilbee commit to build from, or name another tag." >&2
  exit 1
fi

sha="$(awk '/\^\{\}$/ { peeled = $1 } NR == 1 { first = $1 } END { print (peeled != "" ? peeled : first) }' <<< "${lines}")"
if ! [[ "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "lilbee_ref: the lilbee tag ${ref} does not resolve to a commit." >&2
  exit 1
fi

printf 'ref=refs/tags/%s\ntag=%s\ncommit=%s\n' "${ref}" "${ref}" "${sha}"
