#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Day 0 (Kind) + kubeconfig + Day 1 (Argo CD overlay dev).
Day 2: ./scripts/gitops/start.sh dev
Safe to re-run.

Day 0 only: ./scripts/infra/up.sh [kind|aws|openstack]
Teardown: ./scripts/infra/down.sh kind
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "dev" ]]; then
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "Kind infra is a single Terraform environment (kind)." >&2
  echo "Day 1 overlay is always 'dev'. Run: $(basename "$0")" >&2
  usage >&2
  exit 1
fi

echo "==> Validate tools"
"$REPO_ROOT/scripts/lib/require-tools.sh" kubectl helm envsubst

echo "==> Day 0: Kind cluster"
"$REPO_ROOT/scripts/infra/kind/up.sh"

echo "==> Kubeconfig"
KUBECONFIG_FILE="${REPO_ROOT}/sensitive/kind/kubeconfig"
# shellcheck source=scripts/lib/kubeconfig-setup.sh
source "$REPO_ROOT/scripts/lib/kubeconfig-setup.sh" "$KUBECONFIG_FILE"

echo "==> Day 1: Bootstrap (Argo CD)"
"$REPO_ROOT/bootstrap/bootstrap.sh" dev

echo ""
echo "Cluster ready (Kind + Argo overlay dev)."
echo "  Day 2: push gitops/, then ./scripts/gitops/start.sh dev"
echo "  See gitops/README.md"
