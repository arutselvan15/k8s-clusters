#!/usr/bin/env bash
# SSH, inventory and CNI helpers for kubeadm/up.sh and kubeadm/reset.sh.
# Source after REPO_ROOT. Does not call Terraform or a cloud API.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing kubeadm/lib.sh}"

k8s_plat_load_inventory() {
  local file="$1"
  local line key val

  if [[ ! -f "${file}" ]]; then
    echo "Inventory not found: ${file}" >&2
    echo "Run ./scripts/infra/up.sh aws|openstack <cluster> (writes sensitive/<env>/<cluster_name>/cluster.env)." >&2
    return 1
  fi

  SSH_USER="ubuntu"
  SSH_KEY=""
  CONTROL_PLANE_HOST=""
  CONTROL_PLANE_ENDPOINT=""
  WORKER_HOSTS=""
  K8S_VERSION="1.32"
  POD_CIDR="192.168.0.0/16"
  CNI="calico"
  CNI_VERSION=""
  KUBECONFIG_FILE=""
  CLOUD_PROVIDER=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      '' | \#*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    case "${key}" in
      SSH_USER | SSH_KEY | CONTROL_PLANE_HOST | CONTROL_PLANE_ENDPOINT | WORKER_HOSTS | K8S_VERSION | POD_CIDR | CNI | CNI_VERSION | KUBECONFIG_FILE | CLOUD_PROVIDER)
        printf -v "${key}" '%s' "${val}"
        ;;
      CLUSTER_NAME | SSH_CONTROL_PLANE | SSH_WORKER | VPC_CIDR | NETWORK_NAME)
        ;;
      *)
        echo "Ignoring unknown inventory key: ${key}" >&2
        ;;
    esac
  done <"${file}"

  CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-${CONTROL_PLANE_HOST}}"

  # Pinned per CNI: calico is a manifest tag, cilium a chart version.
  CNI="${CNI:-calico}"
  case "${CNI}" in
    calico) CNI_VERSION="${CNI_VERSION:-3.29.3}" ;;
    cilium) CNI_VERSION="${CNI_VERSION:-1.17.18}" ;;
    *)
      echo "CNI must be calico or cilium, got '${CNI}' (${file})" >&2
      return 1
      ;;
  esac

  if [[ -z "${CONTROL_PLANE_HOST}" || "${CONTROL_PLANE_HOST}" == "REPLACE_ME" ]]; then
    echo "Set CONTROL_PLANE_HOST in ${file}" >&2
    return 1
  fi
  if [[ -z "${SSH_KEY}" ]]; then
    echo "Set SSH_KEY in ${file}" >&2
    return 1
  fi

  if [[ "${SSH_KEY}" != /* ]]; then
    SSH_KEY="${REPO_ROOT}/${SSH_KEY}"
  fi
  if [[ -z "${KUBECONFIG_FILE}" ]]; then
    echo "Set KUBECONFIG_FILE in ${file}" >&2
    return 1
  fi
  if [[ "${KUBECONFIG_FILE}" != /* ]]; then
    KUBECONFIG_FILE="${REPO_ROOT}/${KUBECONFIG_FILE}"
  fi
  if [[ ! -f "${SSH_KEY}" ]]; then
    echo "SSH private key not found: ${SSH_KEY}" >&2
    return 1
  fi
  chmod 600 "${SSH_KEY}"

  WORKER_HOST_LIST=()
  local host
  # shellcheck disable=SC2086
  for host in ${WORKER_HOSTS}; do
    if [[ "${host}" == "REPLACE_ME" ]]; then
      echo "Set WORKER_HOSTS in ${file} (space-separated), or leave it empty for control-plane only." >&2
      return 1
    fi
    WORKER_HOST_LIST+=("${host}")
  done

  SSH_KNOWN_HOSTS="$(dirname "${SSH_KEY}")/known_hosts"
  mkdir -p "$(dirname "${SSH_KEY}")" "$(dirname "${KUBECONFIG_FILE}")"
  touch "${SSH_KNOWN_HOSTS}"
  chmod 600 "${SSH_KNOWN_HOSTS}"

  SSH_OPTS=(
    -i "${SSH_KEY}"
    -o IdentitiesOnly=yes
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="${SSH_KNOWN_HOSTS}"
    -o ConnectTimeout=8
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=8
  )
}

k8s_plat_ssh() {
  local ip="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "$@"
}

# Stream a git file to remote bash stdin (no scp).
# Extra args are KEY=VAL env vars (values may contain spaces; quoted for ssh).
k8s_plat_ssh_script() {
  local ip="$1"
  local script="$2"
  shift 2
  local remote="env"
  local pair key val
  if [[ ! -f "${script}" ]]; then
    echo "Missing remote script: ${script}" >&2
    return 1
  fi
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    remote+=" ${key}=$(printf '%q' "${val}")"
  done
  remote+=" bash -s"
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "${remote}" <"${script}"
}

# Install the pod network. Runs on the laptop against the kubeconfig pulled
# after kubeadm init, so only the laptop needs helm — the nodes keep just
# kubeadm/kubelet/kubectl. Nodes stay NotReady until this succeeds.
k8s_plat_install_cni() {
  local kubeconfig="$1"
  case "${CNI}" in
    calico)
      KUBECONFIG="${kubeconfig}" kubectl apply -f \
        "https://raw.githubusercontent.com/projectcalico/calico/v${CNI_VERSION}/manifests/calico.yaml"
      ;;
    cilium)
      k8s_plat_install_cilium "${kubeconfig}"
      ;;
    *)
      echo "Unknown CNI: ${CNI}" >&2
      return 1
      ;;
  esac
}

# kubeProxyReplacement leaves no kube-proxy to reach the API through, so the
# agent needs the endpoint directly. loadBalancer.mode stays snat: DSR answers
# clients with the VIP as source address, which Neutron port security drops on
# the OpenStack tenant network (docs/cilium.md). Tunnel mode because the pod
# CIDR is not routable on that network either.
k8s_plat_install_cilium() {
  local kubeconfig="$1"
  helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null

  KUBECONFIG="${kubeconfig}" helm upgrade --install cilium cilium/cilium \
    --version "${CNI_VERSION}" \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="${CONTROL_PLANE_ENDPOINT}" \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes \
    --set routingMode=tunnel \
    --set tunnelProtocol=vxlan \
    --set loadBalancer.mode=snat \
    --set operator.replicas=1 \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true

  # No helm --wait: it would also block on hubble-relay and hubble-ui, which
  # have no control-plane toleration and stay Pending on a worker_nodes: 0
  # cluster. The agent DaemonSet is what makes nodes Ready, so gate on that.
  KUBECONFIG="${kubeconfig}" kubectl -n kube-system rollout status \
    daemonset/cilium --timeout=5m
}

k8s_plat_wait_ssh() {
  local ip="$1"
  local n=0
  echo "==> Waiting for SSH on ${ip}"
  while [[ "${n}" -lt 36 ]]; do
    if k8s_plat_ssh "${ip}" true >/dev/null 2>&1; then
      echo "    SSH ready: ${SSH_USER}@${ip}"
      return 0
    fi
    n=$((n + 1))
    sleep 5
  done
  echo "SSH did not become ready on ${ip} (user ${SSH_USER}, key ${SSH_KEY})." >&2
  return 1
}
