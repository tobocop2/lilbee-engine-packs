#!/usr/bin/env bash
# Print the build matrix of each job as one line of JSON, from cells.yml:
#
#   bash scripts/plan.sh [engine] [cell] [cells-file]
#
#   {"llama":[...],"mistralrs":[...],"tei":[],"ik":[]}
#
# engine is all (the default), llama, mistralrs, tei or ik. "all" selects llama
# and mistralrs; tei and ik run only by name. An engine that is not selected
# gets an empty list. Each list holds the cells of the engine as the file has
# them, in file order, so a job reads it as its matrix.include.
#
# cell narrows the run to one cell. It is the cell name, or the engine name and
# the cell name joined by a dash (ik-linux-x86_64-cpu). An engine that holds
# no matching cell gets an empty list. A name that matches no cell of any
# selected engine fails, so a typo cannot make a run that builds nothing.

set -euo pipefail

engine="${1:-all}"
cell="${2:-}"
cells="${3:-cells.yml}"

case "${engine}" in
  all) selected=(llama mistralrs) ;;
  llama | mistralrs | tei | ik) selected=("${engine}") ;;
  *)
    echo "plan: unknown engine '${engine}'. Use all, llama, mistralrs, tei or ik." >&2
    exit 1
    ;;
esac

plan='{"llama":[],"mistralrs":[],"tei":[],"ik":[]}'
found=0
for name in "${selected[@]}"; do
  # yq prints each cell as one JSON document; jq filters and joins them. This
  # subset reads the same under the yq on the runner image and under yq's jq
  # wrapper.
  rows="$(yq -r ".engines.${name}.cells[] | @json" "${cells}" \
    | jq -sc --arg engine "${name}" --arg cell "${cell}" \
      '[.[] | select($cell == "" or .cell == $cell or ($engine + "-" + .cell) == $cell)]')"
  [ "${rows}" = "[]" ] || found=1
  plan="$(jq -c --arg engine "${name}" --argjson rows "${rows}" '.[$engine] = $rows' <<< "${plan}")"
done

if [ "${found}" -eq 0 ]; then
  echo "plan: no cell in ${cells} matches engine '${engine}' and cell '${cell}'." >&2
  exit 1
fi

printf '%s\n' "${plan}"
