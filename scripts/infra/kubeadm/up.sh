#!/usr/bin/env bash
# Install Kubernetes with kubeadm on already-running nodes.
# Same args as Day 0: ./scripts/infra/kubeadm/up.sh aws|openstack <cluster>
# Reads sensitive/<env>/<cluster_name>/cluster.env (no Terraform, no cloud API).

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REMOTE_DIR="${REPO_ROOT}/scripts/infra/kubeadm/remote"
PLATFORM=""
CLUSTER=""

usage() {
  cat <<EOF
Usage: ./scripts/infra/kubeadm/up.sh <aws|openstack> <cluster>

Same arguments as ./scripts/infra/up.sh. Loads cluster.env under
sensitive/<env>/<cluster_name>/ written by Day 0.

  ./scripts/infra/up.sh aws k8s-aws
  ./scripts/infra/kubeadm/up.sh aws k8s-aws
  ./scripts/infra/down.sh aws k8s-aws

  ./scripts/infra/kubeadm/up.sh openstack k8s-ocp
  ./scripts/infra/kubeadm/reset.sh aws k8s-aws
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

k8s_plat_load_inventory "${INVENTORY_FILE}"

if [[ "${CLOUD_PROVIDER}" == "external" && "${PLATFORM}" != "openstack" ]]; then
  echo "cloud_provider=external is currently supported only for OpenStack." >&2
  echo "Unset cloud_provider for ${PLATFORM} or add its cloud-controller-manager integration before bootstrapping." >&2
  exit 1
fi

# helm only when the CNI needs it, so a calico cluster keeps the smaller
# toolchain. Inventory is read first because it is what names the CNI.
REQUIRED_TOOLS=(ssh kubectl)
if [[ "${CNI}" == "cilium" ]]; then
  REQUIRED_TOOLS+=(helm)
fi
"$REPO_ROOT/scripts/lib/require-tools.sh" "${REQUIRED_TOOLS[@]}"

echo "==> kubeadm (Kubernetes v${K8S_VERSION})"
echo "    ${K8S_PLAT_CLUSTER_PLATFORM} ${K8S_PLAT_CLUSTER_CONFIG_ID} → ${INVENTORY_FILE}"
echo "    control-plane ${CONTROL_PLANE_HOST} (API ${CONTROL_PLANE_ENDPOINT}:6443)"
echo "    workers       ${#WORKER_HOST_LIST[@]} (${WORKER_HOSTS:-none})"
echo "    pod CIDR      ${POD_CIDR}"
echo "    CNI           ${CNI} ${CNI_VERSION}"
echo "    cloud provider ${CLOUD_PROVIDER:-none (in-tree/no cloud)}"

k8s_plat_wait_ssh "${CONTROL_PLANE_HOST}"
echo "==> 8a prepare control-plane (${CONTROL_PLANE_HOST})"
k8s_plat_ssh_script "${CONTROL_PLANE_HOST}" "${REMOTE_DIR}/prepare.sh" \
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a K8S_VERSION="${K8S_VERSION}" \
  CLOUD_PROVIDER="${CLOUD_PROVIDER}"

host=""
if [[ ${#WORKER_HOST_LIST[@]} -gt 0 ]]; then
  for host in "${WORKER_HOST_LIST[@]}"; do
    k8s_plat_wait_ssh "${host}"
    echo "==> 8a prepare worker (${host})"
    k8s_plat_ssh_script "${host}" "${REMOTE_DIR}/prepare.sh" \
      DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a K8S_VERSION="${K8S_VERSION}" \
      CLOUD_PROVIDER="${CLOUD_PROVIDER}"
  done
fi

echo "==> 8b kubeadm init on control plane"
k8s_plat_ssh_script "${CONTROL_PLANE_HOST}" "${REMOTE_DIR}/init.sh" \
  CP_PUBLIC="${CONTROL_PLANE_ENDPOINT}" POD_CIDR="${POD_CIDR}" CNI="${CNI}" \
  KUBE_PROXY_REPLACEMENT="${CILIUM_KUBE_PROXY_REPLACEMENT}"

if [[ ${#WORKER_HOST_LIST[@]} -gt 0 ]]; then
  echo "==> 8c kubeadm join (${#WORKER_HOST_LIST[@]} worker(s))"
  JOIN_CMD="$(k8s_plat_ssh "${CONTROL_PLANE_HOST}" 'sudo kubeadm token create --print-join-command' | tr -d '\r' | tail -n 1)"
  if [[ "${JOIN_CMD}" != kubeadm\ join* ]]; then
    echo "Did not get a kubeadm join command from the control plane." >&2
    exit 1
  fi
  for host in "${WORKER_HOST_LIST[@]}"; do
    echo "    join ${host}"
    k8s_plat_ssh_script "${host}" "${REMOTE_DIR}/join.sh" JOIN_CMD="${JOIN_CMD}"
  done
else
  echo "==> 8c no workers in inventory; control-plane only"
fi

# Pulled before the CNI step, which runs from here rather than on the node.
# Joining does not need a pod network, so the workers above are already
# registered — they just stay NotReady until 8e lands.
echo "==> 8d kubeconfig on laptop"
mkdir -p "$(dirname "${KUBECONFIG_FILE}")"
k8s_plat_ssh "${CONTROL_PLANE_HOST}" 'sudo cat /etc/kubernetes/admin.conf' >"${KUBECONFIG_FILE}"
chmod 600 "${KUBECONFIG_FILE}"
export KUBECONFIG="${KUBECONFIG_FILE}"
echo "    wrote ${KUBECONFIG_FILE}"

echo "==> 8e pod network (${CNI})"
k8s_plat_install_cni "${KUBECONFIG_FILE}"

ready_timeout="$((300 + 60 * ${#WORKER_HOST_LIST[@]}))"
echo "==> waiting for nodes Ready (timeout ${ready_timeout}s)"
kubectl wait --for=condition=Ready nodes --all --timeout="${ready_timeout}s"
kubectl get nodes -o wide

if [[ "${PLATFORM}" == "openstack" && "${CLOUD_PROVIDER}" == "external" ]]; then
  echo "==> installing OpenStack Cloud Controller Manager"
  "${REPO_ROOT}/scripts/infra/openstack/occm.sh" "${K8S_PLAT_CLUSTER_CONFIG_ID}"
fi

echo ""
echo "Cluster ready (kubeadm)."
echo "  source ${REPO_ROOT}/scripts/lib/kubeconfig-setup.sh ${KUBECONFIG_FILE}"
echo "  kubectl get nodes"

if [[ "${CNI}" == "cilium" ]]; then
  echo ""
  echo "  kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief"
  if [[ "${CILIUM_HUBBLE}" == "true" ]]; then
    echo "  kubectl -n kube-system port-forward svc/hubble-ui 12000:80"
  fi
fi

k8s_plat_s3_offer
