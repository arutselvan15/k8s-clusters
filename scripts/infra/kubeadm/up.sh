#!/usr/bin/env bash
# Install Kubernetes with kubeadm on already-running nodes.
# Reads an inventory file (no Terraform, no cloud API). Streams remote/*.sh over SSH stdin.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REMOTE_DIR="${REPO_ROOT}/scripts/infra/kubeadm/remote"
INVENTORY_FILE="${REPO_ROOT}/.kube/aws-inventory.env"

usage() {
  cat <<EOF
Usage: ./scripts/infra/kubeadm/up.sh [-i inventory-file]

Reads SSH hosts and kubeadm settings from an inventory (KEY=VAL).
Does not call Terraform.

  -i, --inventory FILE   default: .kube/aws-inventory.env
                         OpenStack: .kube/os-inventory.env (written by openstack/up.sh)
  -h, --help

Example: scripts/infra/kubeadm/inventory.example
Reset:   ./scripts/infra/kubeadm/reset.sh [-i FILE]
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
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${INVENTORY_FILE}" != /* ]]; then
  INVENTORY_FILE="${REPO_ROOT}/${INVENTORY_FILE}"
fi

"$REPO_ROOT/scripts/lib/require-tools.sh" ssh kubectl
# shellcheck source=scripts/infra/kubeadm/lib.sh
source "$REPO_ROOT/scripts/infra/kubeadm/lib.sh"
k8s_plat_load_inventory "${INVENTORY_FILE}"

echo "==> kubeadm (Kubernetes v${K8S_VERSION})"
echo "    inventory     ${INVENTORY_FILE}"
echo "    control-plane ${CONTROL_PLANE_HOST} (API ${CONTROL_PLANE_ENDPOINT}:6443)"
echo "    workers       ${#WORKER_HOST_LIST[@]} (${WORKER_HOSTS:-none})"
echo "    pod CIDR      ${POD_CIDR}"

k8s_plat_wait_ssh "${CONTROL_PLANE_HOST}"
echo "==> 8a prepare control-plane (${CONTROL_PLANE_HOST})"
k8s_plat_ssh_script "${CONTROL_PLANE_HOST}" "${REMOTE_DIR}/prepare.sh" \
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a K8S_VERSION="${K8S_VERSION}"

host=""
if [[ ${#WORKER_HOST_LIST[@]} -gt 0 ]]; then
  for host in "${WORKER_HOST_LIST[@]}"; do
    k8s_plat_wait_ssh "${host}"
    echo "==> 8a prepare worker (${host})"
    k8s_plat_ssh_script "${host}" "${REMOTE_DIR}/prepare.sh" \
      DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a K8S_VERSION="${K8S_VERSION}"
  done
fi

echo "==> 8b kubeadm init on control plane"
k8s_plat_ssh_script "${CONTROL_PLANE_HOST}" "${REMOTE_DIR}/init.sh" \
  CP_PUBLIC="${CONTROL_PLANE_ENDPOINT}" POD_CIDR="${POD_CIDR}" CALICO_MANIFEST="${CALICO_MANIFEST}"

if [[ ${#WORKER_HOST_LIST[@]} -gt 0 ]]; then
  echo "==> 8c kubeadm join (${#WORKER_HOST_LIST[@]} worker(s))"
  JOIN_CMD="$(k8s_plat_ssh "${CONTROL_PLANE_HOST}" 'sudo kubeadm token create --print-join-command' | tr -d '\r' | tail -n 1)"
  if [[ "${JOIN_CMD}" != kubeadm\ join* ]]; then
    echo "Did not get a kubeadm join command from the control plane." >&2
    exit 1
  fi
  for host in "${WORKER_HOST_LIST[@]}"; do
    echo "    join ${host}"
    # Do not print JOIN_CMD (bootstrap token).
    k8s_plat_ssh_script "${host}" "${REMOTE_DIR}/join.sh" JOIN_CMD="${JOIN_CMD}"
  done
else
  echo "==> 8c no workers in inventory; control-plane only"
fi

ready_timeout="$((300 + 60 * ${#WORKER_HOST_LIST[@]}))"
echo "==> waiting for nodes Ready (timeout ${ready_timeout}s)"
k8s_plat_ssh "${CONTROL_PLANE_HOST}" "kubectl wait --for=condition=Ready nodes --all --timeout=${ready_timeout}s"
k8s_plat_ssh "${CONTROL_PLANE_HOST}" 'kubectl get nodes -o wide'

echo "==> 8d kubeconfig on laptop"
mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
k8s_plat_ssh "${CONTROL_PLANE_HOST}" 'sudo cat /etc/kubernetes/admin.conf' >"${KUBECONFIG_FILE}"
chmod 600 "${KUBECONFIG_FILE}"

export KUBECONFIG="${KUBECONFIG_FILE}"
echo "    wrote ${KUBECONFIG_FILE}"
kubectl get nodes -o wide

echo ""
echo "Cluster ready (kubeadm)."
echo "  source ${REPO_ROOT}/scripts/lib/kubeconfig-setup.sh ${KUBECONFIG_FILE}"
echo "  kubectl get nodes"
echo "  Day 1: ${REPO_ROOT}/bootstrap/bootstrap.sh dev"
