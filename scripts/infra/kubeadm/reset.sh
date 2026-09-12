#!/usr/bin/env bash
# Undo kubeadm on inventory hosts. Does not destroy VMs or cloud resources.
# Same args as Day 0: ./scripts/infra/kubeadm/reset.sh aws|openstack <cluster>
# Streams remote/reset.sh over SSH stdin (no scp).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REMOTE_DIR="${REPO_ROOT}/scripts/infra/kubeadm/remote"
PLATFORM=""
CLUSTER=""

usage() {
  cat <<EOF
Usage: ./scripts/infra/kubeadm/reset.sh <aws|openstack> <cluster>

Same arguments as ./scripts/infra/up.sh / kubeadm/up.sh / down.sh.
kubeadm reset on workers, then the control plane. Removes the kubeconfig
listed in cluster.env. VMs stay running.

  ./scripts/infra/kubeadm/reset.sh aws k8s-aws
  ./scripts/infra/kubeadm/reset.sh openstack k8s-ocp
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -c | --cluster)
      CLUSTER="${2:?cluster config required}"
      shift
      ;;
    aws | openstack)
      PLATFORM="$1"
      ;;
    *)
      if [[ -z "${CLUSTER}" ]]; then
        CLUSTER="$1"
      else
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

# shellcheck source=scripts/lib/paths.sh
source "$REPO_ROOT/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "$REPO_ROOT/scripts/lib/cluster-config.sh"
# shellcheck source=scripts/infra/kubeadm/lib.sh
source "$REPO_ROOT/scripts/infra/kubeadm/lib.sh"

k8s_plat_bind_kubeadm_inventory "${PLATFORM}" "${CLUSTER}" || {
  usage >&2
  exit 1
}
INVENTORY_FILE="${K8S_PLAT_CLUSTER_ENV}"

"$REPO_ROOT/scripts/lib/require-tools.sh" ssh
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

echo "Kubernetes removed from the nodes."
echo "Reinstall: ./scripts/infra/kubeadm/up.sh ${K8S_PLAT_CLUSTER_PLATFORM} ${K8S_PLAT_CLUSTER_CONFIG_ID}"
