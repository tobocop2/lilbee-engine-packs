#!/usr/bin/env bash
# Stop the publish job unless the plan succeeded and every build job that the plan gave cells succeeded.
#
#   bash scripts/needs_ok.sh '<toJSON(needs)>'
#
# The outputs of the plan job hold the cells of each engine (scripts/plan.sh). The llama engine runs in the
# job named cell, and every other engine in the job of its own name.
# A job whose list is empty is skipped on purpose, so skipped is allowed there.
# A cancelled or failed job blocks the publish: a cancelled job is not a failure to GitHub, and
# the "failure" test of the job condition let a run publish 8 of 9 wheels.
# A job that the plan gave cells must be success, so such a job that GitHub skipped blocks the publish too.
# A plan that gives no job a cell blocks the publish, because the run built no wheel.

set -euo pipefail

needs="${1:?usage: needs_ok.sh <toJSON(needs)>}"

if ! command -v jq > /dev/null; then
  echo "needs_ok: jq is not installed, so the release is not published." >&2
  exit 1
fi

blocked="$(jq -r '
  (.plan.outputs // {}) as $plan
  | [to_entries[] | select(.key != "plan")
     | (if .key == "cell" then "llama" else .key end) as $engine
     | .planned = (($plan[$engine] // "[]") != "[]")] as $builds
  | (if .plan.result != "success" then "plan: \(.plan.result // "missing")" else empty end),
    ($builds[] | select(.value.result != "success" and (.planned or .value.result != "skipped"))
     | "\(.key): \(.value.result)\(if .planned and .value.result == "skipped" then ", and the plan gives it cells" else "" end)"),
    (if [$builds[] | select(.planned)] == [] then "no build job: the plan gives no job a cell" else empty end)
' <<< "${needs}")"

if [[ -n "${blocked}" ]]; then
  echo "needs_ok: the release is not published, because these jobs did not succeed:" >&2
  echo "${blocked}" >&2
  exit 1
fi
