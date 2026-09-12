#!/bin/bash
#
# Export KUBECONFIG for the current shell. Must be sourced.
#
#   source scripts/lib/kubeconfig-setup.sh /path/to/kubeconfig.yaml

set -euo pipefail

usage() {
  cat <<EOF
Usage (source so export applies to your shell):
  source $(basename "$0") <kubeconfig-file-path>
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Source this script:" >&2
  echo "  source ${BASH_SOURCE[0]} <kubeconfig-file-path>" >&2
  usage >&2
  exit 1
fi

KUBECONFIG_FILE="${1:?kubeconfig file path required}"
KUBECONFIG_FILE="${KUBECONFIG_FILE/#\~/$HOME}"

if [[ ! -f "$KUBECONFIG_FILE" ]]; then
  echo "Kubeconfig not found: $KUBECONFIG_FILE" >&2
  echo "Build the cluster first: ./scripts/infra/up.sh [kind|aws|openstack]" >&2
  return 1 2>/dev/null || exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

echo "KUBECONFIG=$KUBECONFIG"
echo "Node connectivity test:"
kubectl get nodes
