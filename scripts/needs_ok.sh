#!/usr/bin/env bash
# Stop the publish job unless every job it needs succeeded or was skipped, and every selected engine succeeded.
#
#   bash scripts/needs_ok.sh '<toJSON(needs)>' <engine>
#
# engine is the engine input of the run: all, llama, mistralrs, tei or ik. "all" selects llama and mistralrs.
# The llama engine runs in the job named cell.
# A job of an engine that the run did not select is skipped on purpose, so skipped is allowed there.
# A cancelled or failed job blocks the publish: a cancelled job is not a failure to GitHub, and
# the "failure" test of the job condition let a run publish 8 of 9 wheels.
# A job of a selected engine must be success, so a selected job that GitHub skipped blocks the publish too.

set -euo pipefail

needs="${1:?usage: needs_ok.sh <toJSON(needs)> <engine>}"
engine="${2:?usage: needs_ok.sh <toJSON(needs)> <engine>}"

case "${engine}" in
  all) selected=(cell mistralrs) ;;
  llama) selected=(cell) ;;
  mistralrs | tei | ik) selected=("${engine}") ;;
  *)
    echo "needs_ok: unknown engine '${engine}'." >&2
    exit 1
    ;;
esac

if ! command -v jq > /dev/null; then
  echo "needs_ok: jq is not installed, so the release is not published." >&2
  exit 1
fi

blocked="$(jq -r 'to_entries[] | select(.value.result != "success" and .value.result != "skipped") | "\(.key): \(.value.result)"' <<< "${needs}")"
for job in "${selected[@]}"; do
  result="$(jq -r --arg job "${job}" '.[$job].result // "missing"' <<< "${needs}")"
  if [[ "${result}" == "skipped" || "${result}" == "missing" ]]; then
    blocked+="${blocked:+$'\n'}${job}: ${result}, and the run selects it"
  fi
done

if [[ -n "${blocked}" ]]; then
  echo "needs_ok: the release is not published, because these jobs did not succeed:" >&2
  echo "${blocked}" >&2
  exit 1
fi
