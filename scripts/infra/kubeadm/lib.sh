#!/usr/bin/env bash
# SSH + inventory helpers for kubeadm/up.sh and kubeadm/reset.sh.
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
  CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml"
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
      SSH_USER | SSH_KEY | CONTROL_PLANE_HOST | CONTROL_PLANE_ENDPOINT | WORKER_HOSTS | K8S_VERSION | POD_CIDR | CALICO_MANIFEST | KUBECONFIG_FILE | CLOUD_PROVIDER)
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
