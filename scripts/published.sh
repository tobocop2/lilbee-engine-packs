#!/usr/bin/env bash
# Print each asset that a release of the repository ships, as the file that scripts/plan.sh reads:
#
#   bash scripts/published.sh > published.txt
#
#   lilbee_engine_tei-1.9.4-1.cpu-py3-none-manylinux_2_34_x86_64.whl engine-packs-20261118
#
# One line holds the asset name and the tag of its release. The script reads every page of the
# release list, the list that the clash check of scripts/publish.sh reads. A token with contents: read
# lists no draft release, so the clash check stays the last guard for a draft.
# GITHUB_REPOSITORY (owner/name) names the repository, and GH_TOKEN lets gh read it.
# A failed read fails the script, so the plan never takes an unread list for an empty one.

set -euo pipefail

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "published: GITHUB_REPOSITORY is empty." >&2
  exit 2
fi

# The jq expression is for gh, so the shell must not expand it.
# shellcheck disable=SC2016
gh api "repos/${GITHUB_REPOSITORY}/releases" --paginate \
  --jq '.[] | .tag_name as $tag | .assets[] | "\(.name) \($tag)"'
