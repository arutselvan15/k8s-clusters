#!/usr/bin/env bash
# Undo kubeadm on inventory hosts. Does not destroy VMs or cloud resources.
# Streams remote/reset.sh over SSH stdin (no scp).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REMOTE_DIR="${REPO_ROOT}/scripts/infra/kubeadm/remote"
INVENTORY_FILE=""
CLUSTER_SPEC="default"

usage() {
  cat <<EOF
Usage: ./scripts/infra/kubeadm/reset.sh [cluster] [-i inventory-file]

kubeadm reset on each worker, then the control plane. Removes the kubeconfig
from inventory. VMs stay running.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -i | --inventory)
      INVENTORY_FILE="${2:?inventory file required}"
      shift
      ;;
    -c | --cluster)
      CLUSTER_SPEC="${2:?cluster config required}"
      shift
      ;;
    *)
      CLUSTER_SPEC="$1"
      ;;
  esac
  shift
done

# shellcheck source=scripts/lib/paths.sh
source "$REPO_ROOT/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "$REPO_ROOT/scripts/lib/cluster-config.sh"

if [[ -z "${INVENTORY_FILE}" ]]; then
  k8s_plat_resolve_kubeadm_inventory "${CLUSTER_SPEC}"
  INVENTORY_FILE="${K8S_PLAT_KUBEADM_INVENTORY}"
elif [[ "${INVENTORY_FILE}" != /* ]]; then
  INVENTORY_FILE="${REPO_ROOT}/${INVENTORY_FILE}"
fi

"$REPO_ROOT/scripts/lib/require-tools.sh" ssh
# shellcheck source=scripts/infra/kubeadm/lib.sh
source "$REPO_ROOT/scripts/infra/kubeadm/lib.sh"
k8s_plat_load_inventory "${INVENTORY_FILE}"

reset_node() {
  local ip="$1"
  local role="$2"
  echo "==> kubeadm reset ${role} (${ip})"
  k8s_plat_wait_ssh "${ip}"
  k8s_plat_ssh_script "${ip}" "${REMOTE_DIR}/reset.sh"
}

host=""
if [[ ${#WORKER_HOST_LIST[@]} -gt 0 ]]; then
  for host in "${WORKER_HOST_LIST[@]}"; do
    reset_node "${host}" "worker"
  done
fi
reset_node "${CONTROL_PLANE_HOST}" "control-plane"

if [[ -f "${KUBECONFIG_FILE}" ]]; then
  rm -f "${KUBECONFIG_FILE}"
  echo "Removed ${KUBECONFIG_FILE}"
fi

echo "Kubernetes removed from the nodes. Reinstall: ./scripts/infra/kubeadm/up.sh"
