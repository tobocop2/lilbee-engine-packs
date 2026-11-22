#!/usr/bin/env bash
# Install the pinned yq into one directory, for a Windows x86_64 computer (the runner image has none):
#
#   bash scripts/install_yq.sh <bin-dir>
#
# The download is checked against a sha256. Put <bin-dir> on PATH.

set -euo pipefail

dir="${1:?usage: install_yq.sh <bin-dir>}"

version=4.54.3
sha256=066ea0a09a282e47588ec1e1867280ff5ede458f7183617a2d99012e4e34f18a

mkdir -p "${dir}"
curl -fsSL --retry 5 --retry-all-errors -o "${dir}/yq.exe" \
  "https://github.com/mikefarah/yq/releases/download/v${version}/yq_windows_amd64.exe"
(cd "${dir}" && echo "${sha256}  yq.exe" | sha256sum -c --quiet -)
