#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Run Kyverno Chainsaw e2e tests under gitops/chainsaw/ against the current cluster.

Requires: chainsaw on PATH, KUBECONFIG set (see scripts/lib/kubeconfig-setup.sh).

Example:
  source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig
  $(basename "$0")
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  usage >&2
  exit 1
fi

"$REPO_ROOT/scripts/lib/require-tools.sh" chainsaw kubectl

echo "==> Chainsaw: gitops/chainsaw"
exec chainsaw test "$REPO_ROOT/gitops/chainsaw"
