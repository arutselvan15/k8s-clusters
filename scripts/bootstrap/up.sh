#!/bin/bash

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [cluster]

Day 0 (Kind) + kubeconfig + Day 1 (Argo CD overlay dev).
Day 2: ./scripts/gitops/start.sh dev
Safe to re-run.

cluster   Kind config id (optional if clusters/kind/ has exactly one dir)

Day 0 only: ./scripts/infra/up.sh [kind|aws|openstack]
Teardown: ./scripts/infra/down.sh kind
EOF
}

CLUSTER=""
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
# Historic: first arg "dev" meant the Day 1 overlay, not the Kind config id.
if [[ "${1:-}" == "dev" ]]; then
  shift
fi
if [[ $# -gt 0 ]]; then
  CLUSTER="$1"
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "Unexpected argument: $1" >&2
  usage >&2
  exit 1
fi

CLUSTER="$(k8s_plat_effective_cluster_spec kind "${CLUSTER}")" || exit 1

echo "==> Validate tools"
"$REPO_ROOT/scripts/lib/require-tools.sh" kubectl helm envsubst

echo "==> Day 0: Kind cluster"
"$REPO_ROOT/scripts/infra/up.sh" kind "${CLUSTER}"

echo "==> Kubeconfig"
k8s_plat_resolve_cluster_config kind "${CLUSTER}"
k8s_plat_apply_cluster_outputs
KUBECONFIG_FILE="${K8S_PLAT_CLUSTER_KUBECONFIG}"
# shellcheck source=scripts/lib/kubeconfig-setup.sh
source "$REPO_ROOT/scripts/lib/kubeconfig-setup.sh" "$KUBECONFIG_FILE"

echo "==> Day 1: Bootstrap (Argo CD)"
"$REPO_ROOT/bootstrap/bootstrap.sh" dev

echo ""
echo "Cluster ready (Kind + Argo overlay dev)."
echo "  Day 2: push gitops/, then ./scripts/gitops/start.sh dev"
echo "  See gitops/README.md"
