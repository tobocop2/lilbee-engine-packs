#!/usr/bin/env bash
# Print the build matrix of each job as one line of JSON, from cells.yml:
#
#   bash scripts/plan.sh [engine] [cell] [cells-file] [published-file]
#
#   {"llama":[...],"mistralrs":[...],"tei":[],"ik":[]}
#
# engine is all (the default) or the name of one engine of the cells file. "all" selects every engine
# of the file. The output has one key for each engine of the file, and an engine that is not selected
# gets an empty list. Each list holds the cells of the engine as the file has them, in file order, so a
# job reads it as its matrix.include. A job whose list is empty does not run.
#
# cell narrows the run to one cell. It is the cell name, or the engine name and
# the cell name joined by a dash (ik-linux-x86_64-cpu). An engine that holds
# no matching cell gets an empty list. A name that matches no cell of any
# selected engine fails, so a typo cannot make a run that builds nothing.
#
# published-file holds one "<wheel file name> <release tag>" line for each wheel that a release ships
# (scripts/published.sh writes it). The plan drops each selected cell whose wheel file name
# (scripts/wheel_name.bash) is in the file, and names the cell and its release on stderr and in the
# step summary. A run that names one cell fails when that cell is published. To build a published cell
# again, raise its build number. Without the file, the plan drops no cell.

set -euo pipefail

engine="${1:-all}"
cell="${2:-}"
cells="${3:-cells.yml}"
published="${4:-}"

# shellcheck source=scripts/wheel_name.bash
source "$(dirname "${BASH_SOURCE[0]}")/wheel_name.bash"

engines="$(yq -r '.engines | @json' "${cells}" | tr -d '\r')"
if [ "${engine}" != all ] && ! jq -e --arg engine "${engine}" 'has($engine)' <<< "${engines}" > /dev/null; then
  echo "plan: unknown engine '${engine}'. Use all, $(jq -r 'keys_unsorted | join(", ")' <<< "${engines}")." >&2
  exit 1
fi

shipped='{}'
if [ -n "${published}" ]; then
  shipped="$(jq -Rn '[inputs | select(length > 0) | split(" ") | {key: .[0], value: .[1]}] | from_entries' \
    < "${published}")"
fi

# Each selected cell that matches the cell name, with its id, its wheel file name and the release that ships it.
rows="$(jq -c --arg engine "${engine}" --arg cell "${cell}" --argjson shipped "${shipped}" "${WHEEL_NAME_JQ}"'
  [to_entries[] | .key as $name | .value.pins as $pins
   | select($engine == "all" or $engine == $name)
   | .value.cells[] | select($cell == "" or .cell == $cell or ($name + "-" + .cell) == $cell)
   | {engine: $name, row: .,
      id: (if .cell | startswith($name + "-") then .cell else $name + "-" + .cell end),
      wheel: wheel_name($name; $pins)}
   | .release = $shipped[.wheel]]' <<< "${engines}")"

if [ "$(jq 'length' <<< "${rows}")" -eq 0 ]; then
  echo "plan: no cell in ${cells} matches engine '${engine}' and cell '${cell}'." >&2
  exit 1
fi

skipped="$(jq -r '.[] | select(.release != null) | "\(.id): \(.wheel) is in the release \(.release)"' <<< "${rows}")"
if [ -n "${skipped}" ]; then
  if [ -n "${cell}" ]; then
    echo "plan: the cell is published, so the run would build nothing. Raise its build number." >&2
    echo "${skipped}" >&2
    exit 1
  fi
  echo "plan: these cells are published, so the run does not build them:" >&2
  echo "${skipped}" >&2
  {
    echo "Published cells that the run does not build:"
    while IFS= read -r line; do echo "- ${line}"; done <<< "${skipped}"
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi

jq -c --argjson rows "${rows}" \
  'with_entries(.key as $name | .value = [$rows[] | select(.engine == $name and .release == null) | .row])' \
  <<< "${engines}"
