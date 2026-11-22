#!/usr/bin/env bash
# Install the pinned shellcheck and actionlint into one directory, for a Linux x86_64 computer:
#
#   bash scripts/install_lint_tools.sh <bin-dir>
#
# Each download is checked against a sha256 before it is unpacked. Put <bin-dir> first on PATH.
# The versions here must equal SHELLCHECK_VERSION and ACTIONLINT_VERSION in the Makefile.

set -euo pipefail

dir="${1:?usage: install_lint_tools.sh <bin-dir>}"

shellcheck_version=0.11.0
shellcheck_sha256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
actionlint_version=1.7.12
actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8

if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
  echo "install_lint_tools: this script installs Linux x86_64 builds only. Install shellcheck ${shellcheck_version} and actionlint ${actionlint_version} by hand." >&2
  exit 1
fi

work="$(mktemp -d)"
mkdir -p "${dir}"

fetch() {
  local url="$1" sha256="$2" file="$3"
  curl -fsSL --retry 5 --retry-all-errors -o "${work}/${file}" "${url}"
  echo "${sha256}  ${work}/${file}" | sha256sum -c --quiet -
}

fetch "https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.linux.x86_64.tar.xz" \
  "${shellcheck_sha256}" shellcheck.tar.xz
tar -xJf "${work}/shellcheck.tar.xz" -C "${work}"
install -m 0755 "${work}/shellcheck-v${shellcheck_version}/shellcheck" "${dir}/shellcheck"

fetch "https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_linux_amd64.tar.gz" \
  "${actionlint_sha256}" actionlint.tar.gz
tar -xzf "${work}/actionlint.tar.gz" -C "${work}" actionlint
install -m 0755 "${work}/actionlint" "${dir}/actionlint"
