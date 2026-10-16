#!/usr/bin/env bash
# Shared helpers for scripts/infra/openshift/{ocp.sh,down.sh} and phases/*.
# Source after REPO_ROOT is set. Phases run in a subshell with this loaded.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing openshift/lib.sh}"

# shellcheck source=scripts/lib/os-env.sh
source "${REPO_ROOT}/scripts/lib/os-env.sh"

OCP_SCRIPT_DIR="${REPO_ROOT}/scripts/infra/openshift"
OCP_TF_DIR="${REPO_ROOT}/infra/terraform/environments/openshift"
OCP_PULL_SECRET="${K8S_PLAT_SENSITIVE_DIR}/openshift/pull-secret.json"

ocp_die() {
  echo "ERROR: $*" >&2
  exit 1
}

ocp_step() {
  echo "==> $*"
}

# Read a key from the cluster YAML. With a second argument the key is
# optional and that is the default; without one, a missing key is an error.
ocp_cfg() {
  local key="$1"
  if [[ $# -ge 2 ]]; then
    k8s_plat_yaml_get "${K8S_PLAT_CLUSTER_CONFIG}" "${key}" 2>/dev/null || printf '%s' "$2"
  else
    k8s_plat_yaml_require "${K8S_PLAT_CLUSTER_CONFIG}" "${key}"
  fi
}

ocp_require_match() {
  local key="$1" value="$2" regex="$3" hint="$4"
  if [[ ! "${value}" =~ ${regex} ]]; then
    echo "${key} in ${K8S_PLAT_CLUSTER_CONFIG}: ${hint} (got '${value}')" >&2
    return 1
  fi
}

ocp_ipv4_re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
ocp_cidr_re='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'

# Resolve clusters/openshift/<id>/config.yaml, then load and validate every
# knob into OCP_* so phases never parse YAML themselves.
ocp_load_config() {
  local spec="${1:-}"
  spec="$(k8s_plat_effective_cluster_spec openshift "${spec}")" || return 1
  k8s_plat_resolve_cluster_config openshift "${spec}" || return 1
  k8s_plat_apply_cluster_outputs >/dev/null || return 1

  OCP_CLUSTER_NAME="${K8S_PLAT_CLUSTER_NAME}"
  OCP_CLUSTER_ID="${K8S_PLAT_CLUSTER_CONFIG_ID}"
  OCP_BASE_DOMAIN="$(ocp_cfg base_domain)" || return 1
  OCP_CLOUD="$(ocp_cfg cloud)" || return 1
  export OS_CLOUD="${OCP_CLOUD}"

  OCP_RELEASE="$(ocp_cfg openshift.release)" || return 1
  OCP_CP_REPLICAS="$(ocp_cfg openshift.control_plane.replicas)" || return 1
  OCP_CP_FLAVOR="$(ocp_cfg openshift.control_plane.flavor)" || return 1
  OCP_COMPUTE_REPLICAS="$(ocp_cfg openshift.compute.replicas)" || return 1
  OCP_COMPUTE_FLAVOR="$(ocp_cfg openshift.compute.flavor)" || return 1
  OCP_ROOT_VOLUME_GB="$(ocp_cfg openshift.root_volume_gb)" || return 1
  OCP_VOLUME_TYPE="$(ocp_cfg openshift.volume_type)" || return 1
  OCP_CLUSTER_NETWORK="$(ocp_cfg openshift.cluster_network)" || return 1
  OCP_HOST_PREFIX="$(ocp_cfg openshift.host_prefix)" || return 1
  OCP_SERVICE_NETWORK="$(ocp_cfg openshift.service_network)" || return 1
  OCP_CLUSTER_OS_IMAGE="$(ocp_cfg openshift.cluster_os_image "")"
  OCP_HTTP_PROXY="$(ocp_cfg openshift.proxy.http "")"
  OCP_HTTPS_PROXY="$(ocp_cfg openshift.proxy.https "")"
  OCP_NO_PROXY="$(ocp_cfg openshift.proxy.no_proxy "")"
  OCP_CNI="$(ocp_cfg openshift.cni OVNKubernetes)"

  # create: Terraform builds the tenant network, router and 3 floating IPs.
  # existing: it joins a provider network that already routes, and the flow
  # uses no floating IPs at all (see infra/terraform/environments/openshift).
  OCP_NETWORK_MODE="$(ocp_cfg terraform.network.mode create)"
  OCP_API_VIP="$(ocp_cfg terraform.network.api_vip)" || return 1
  OCP_INGRESS_VIP="$(ocp_cfg terraform.network.ingress_vip)" || return 1
  OCP_EXISTING_NETWORK=""
  OCP_EXISTING_SUBNET=""
  OCP_NET_CIDR=""
  OCP_DHCP_START=""
  OCP_DHCP_END=""
  OCP_EXTERNAL_NETWORK=""
  OCP_DNS_NAMESERVERS=""
  if [[ "${OCP_NETWORK_MODE}" == "existing" ]]; then
    OCP_EXISTING_NETWORK="$(ocp_cfg terraform.network.name)" || return 1
    OCP_EXISTING_SUBNET="$(ocp_cfg terraform.network.subnet)" || return 1
  else
    OCP_NET_CIDR="$(ocp_cfg terraform.network.cidr)" || return 1
    OCP_DHCP_START="$(ocp_cfg terraform.network.dhcp_start)" || return 1
    OCP_DHCP_END="$(ocp_cfg terraform.network.dhcp_end)" || return 1
    OCP_EXTERNAL_NETWORK="$(ocp_cfg terraform.network.external_network)" || return 1
    OCP_DNS_NAMESERVERS="$(ocp_cfg terraform.network.dns_nameservers)" || return 1
  fi

  OCP_JUMP_IMAGE="$(ocp_cfg terraform.image.name)" || return 1
  OCP_JUMP_IMAGE_MOST_RECENT="$(ocp_cfg terraform.image.most_recent true)"
  OCP_JUMP_FLAVOR="$(ocp_cfg terraform.jumphost.flavor)" || return 1
  OCP_JUMP_ROOT_GB="$(ocp_cfg terraform.jumphost.root_volume_gb)" || return 1
  OCP_SSH_USER="$(ocp_cfg terraform.ssh.user)" || return 1
  OCP_SSH_KEY_ALGORITHM="$(ocp_cfg terraform.ssh.key_algorithm ED25519)"
  # One CIDR, or a comma-separated list when you reach the jump host from
  # more than one range (VPN pool and office network, say).
  OCP_ADMIN_CIDR="$(ocp_cfg terraform.admin_cidr)" || return 1
  OCP_ADMIN_CIDRS="$(tr ', ' '\n\n' <<<"${OCP_ADMIN_CIDR}" | grep -v '^$' | tr '\n' ' ')"
  OCP_ADMIN_CIDRS="${OCP_ADMIN_CIDRS% }"

  OCP_CILIUM_VERSION=""
  OCP_CILIUM_SOURCE=""
  OCP_CILIUM_KPR="false"
  OCP_CILIUM_HUBBLE="false"
  if [[ "${OCP_CNI}" == "Cilium" ]]; then
    OCP_CILIUM_VERSION="$(ocp_cfg openshift.cilium.version)" || return 1
    OCP_CILIUM_SOURCE="$(ocp_cfg openshift.cilium.source helm)"
    OCP_CILIUM_KPR="$(ocp_cfg openshift.cilium.kube_proxy_replacement true)"
    OCP_CILIUM_HUBBLE="$(ocp_cfg openshift.cilium.hubble true)"
  fi

  # OpenStack uses OnPremClusterName: DNS label, no dots, at most 54 characters
  # (63-byte DNS label minus the 9-character "*.apps" record).
  ocp_require_match cluster_name "${OCP_CLUSTER_NAME}" '^[a-z0-9]([-a-z0-9]{0,52}[a-z0-9])?$' \
    "lowercase DNS label, 54 characters or fewer, no dots" || return 1
  ocp_require_match base_domain "${OCP_BASE_DOMAIN}" '^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$' \
    "DNS domain such as example.lab (avoid .local: macOS sends it to mDNS)" || return 1
  ocp_require_match openshift.release "${OCP_RELEASE}" '^4\.[0-9]+\.[0-9]+$' "exact release like 4.22.17" || return 1
  ocp_require_match openshift.control_plane.replicas "${OCP_CP_REPLICAS}" '^(1|3)$' "1 or 3" || return 1
  ocp_require_match openshift.compute.replicas "${OCP_COMPUTE_REPLICAS}" '^[0-9]+$' "integer" || return 1
  ocp_require_match openshift.root_volume_gb "${OCP_ROOT_VOLUME_GB}" '^[0-9]+$' "integer" || return 1
  ocp_require_match openshift.host_prefix "${OCP_HOST_PREFIX}" '^[0-9]{2}$' "prefix length like 23" || return 1
  ocp_require_match openshift.cluster_network "${OCP_CLUSTER_NETWORK}" "${ocp_cidr_re}" "CIDR" || return 1
  ocp_require_match openshift.service_network "${OCP_SERVICE_NETWORK}" "${ocp_cidr_re}" "CIDR" || return 1
  local cidr
  ocp_require_match terraform.network.mode "${OCP_NETWORK_MODE}" '^(create|existing)$' "create or existing" || return 1
  if [[ "${OCP_NETWORK_MODE}" == "create" ]]; then
    ocp_require_match terraform.network.cidr "${OCP_NET_CIDR}" "${ocp_cidr_re}" "CIDR" || return 1
    ocp_require_match terraform.network.dhcp_start "${OCP_DHCP_START}" "${ocp_ipv4_re}" "IPv4 address" || return 1
    ocp_require_match terraform.network.dhcp_end "${OCP_DHCP_END}" "${ocp_ipv4_re}" "IPv4 address" || return 1
  fi
  ocp_require_match terraform.network.api_vip "${OCP_API_VIP}" "${ocp_ipv4_re}" "IPv4 address" || return 1
  ocp_require_match terraform.network.ingress_vip "${OCP_INGRESS_VIP}" "${ocp_ipv4_re}" "IPv4 address" || return 1
  for cidr in ${OCP_ADMIN_CIDRS}; do
    ocp_require_match terraform.admin_cidr "${cidr}" "${ocp_cidr_re}" "CIDR, or a comma-separated list of them" || return 1
    if [[ "${cidr}" == "0.0.0.0/0" ]]; then
      echo "terraform.admin_cidr must not be 0.0.0.0/0: that opens SSH on the jump host to the Internet" >&2
      return 1
    fi
  done
  ocp_require_match openshift.cni "${OCP_CNI}" '^(OVNKubernetes|Cilium)$' \
    "OVNKubernetes or Cilium" || return 1
  if [[ "${OCP_CNI}" == "Cilium" ]]; then
    ocp_require_match openshift.cilium.version "${OCP_CILIUM_VERSION}" '^1\.[0-9]+\.[0-9]+$' "chart version like 1.19.8" || return 1
    ocp_require_match openshift.cilium.source "${OCP_CILIUM_SOURCE}" '^helm$' "only 'helm' is implemented" || return 1
    ocp_require_match openshift.cilium.kube_proxy_replacement "${OCP_CILIUM_KPR}" '^(true|false)$' "true or false" || return 1
    ocp_require_match openshift.cilium.hubble "${OCP_CILIUM_HUBBLE}" '^(true|false)$' "true or false" || return 1
  fi
  # 0 omits rootVolume from install-config: nodes boot from the flavor's local
  # disk and use no Cinder quota. Anything else is a volume, and OpenShift's
  # minimum for one is 100 GB.
  if (( OCP_ROOT_VOLUME_GB != 0 && OCP_ROOT_VOLUME_GB < 100 )); then
    echo "openshift.root_volume_gb must be 0 (boot from the flavor disk) or >= 100 (OpenShift minimum)" >&2
    return 1
  fi

  # OpenShift 4.y ships Kubernetes 1.(y+13): 4.20 -> 1.33, 4.22 -> 1.35.
  # helm template needs it to pick API versions the cluster will serve.
  local minor="${OCP_RELEASE#4.}"
  minor="${minor%%.*}"
  OCP_KUBE_VERSION="1.$((minor + 13)).0"

  OCP_API_HOST="api.${OCP_CLUSTER_NAME}.${OCP_BASE_DOMAIN}"
  OCP_API_INT_HOST="api-int.${OCP_CLUSTER_NAME}.${OCP_BASE_DOMAIN}"
  OCP_APPS_DOMAIN="apps.${OCP_CLUSTER_NAME}.${OCP_BASE_DOMAIN}"

  OCP_OUT_DIR="${K8S_PLAT_CLUSTER_DIR}"
  OCP_PHASE_DIR="${OCP_OUT_DIR}/phases"
  OCP_ENV_FILE="${OCP_OUT_DIR}/cluster.env"
  OCP_SSH_KEY="${OCP_OUT_DIR}/ssh.pem"
  OCP_KNOWN_HOSTS="${OCP_OUT_DIR}/known_hosts"
  OCP_TFSTATE="${K8S_PLAT_TFSTATE}"

  # Everything the installer owns lives on the jump host under this dir.
  OCP_REMOTE_WORK="/home/${OCP_SSH_USER}/ocp/${OCP_CLUSTER_NAME}"
  OCP_REMOTE_INSTALL="${OCP_REMOTE_WORK}/install"
  mkdir -p "${OCP_PHASE_DIR}"
}

# Terraform -var flags for infra/terraform/environments/openshift. Shared by
# phase 10 (apply) and down.sh (destroy) so the two cannot drift.
ocp_tf_vars() {
  local dns_list admin_list
  dns_list="$(tr -d ' ' <<<"${OCP_DNS_NAMESERVERS}" | awk -F, '{for (i = 1; i <= NF; i++) if ($i != "") printf "%s\"%s\"", (i > 1 ? "," : ""), $i}')"
  admin_list="$(awk '{for (i = 1; i <= NF; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), $i}' <<<"${OCP_ADMIN_CIDRS}")"
  OCP_TF_VARS=(
    -var "cloud=${OCP_CLOUD}"
    -var "cluster_name=${OCP_CLUSTER_NAME}"
    -var "ssh_private_key_path=${OCP_SSH_KEY}"
    -var "ssh_key_algorithm=${OCP_SSH_KEY_ALGORITHM}"
    -var "admin_cidrs=[${admin_list}]"
    -var "network_mode=${OCP_NETWORK_MODE}"
    -var "existing_network=${OCP_EXISTING_NETWORK}"
    -var "existing_subnet=${OCP_EXISTING_SUBNET}"
    -var "network_cidr=${OCP_NET_CIDR}"
    -var "dhcp_start=${OCP_DHCP_START}"
    -var "dhcp_end=${OCP_DHCP_END}"
    -var "dns_nameservers=[${dns_list}]"
    -var "external_network=${OCP_EXTERNAL_NETWORK}"
    -var "jumphost_image=${OCP_JUMP_IMAGE}"
    -var "jumphost_image_most_recent=${OCP_JUMP_IMAGE_MOST_RECENT}"
    -var "jumphost_flavor=${OCP_JUMP_FLAVOR}"
    -var "jumphost_root_volume_gb=${OCP_JUMP_ROOT_GB}"
  )
}

# cluster.env is written by phase 10 from Terraform outputs. Parsed, not
# sourced, so a stray value can never run as code.
ocp_load_outputs() {
  local line key val
  if [[ ! -f "${OCP_ENV_FILE}" ]]; then
    ocp_die "Missing ${OCP_ENV_FILE}. Run phase 10-infra first."
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in '' | \#*) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    case "${key}" in
      JUMP_SSH_IP | JUMP_FIP | JUMP_FIXED_IP | API_FIP | INGRESS_FIP | MACHINE_CIDR | NETWORK_NAME | SUBNET_NAME | SSH_PUBLIC_KEY)
        printf -v "OCP_${key}" '%s' "${val}"
        ;;
    esac
  done <"${OCP_ENV_FILE}"
  # network_mode=existing has no floating IP: the jump host's fixed address on
  # the provider network is the one that routes.
  : "${OCP_JUMP_SSH_IP:=${OCP_JUMP_FIP:-}}"
  [[ -n "${OCP_JUMP_SSH_IP}" ]] || ocp_die "JUMP_SSH_IP missing in ${OCP_ENV_FILE}"
  : "${OCP_MACHINE_CIDR:=${OCP_NET_CIDR}}"
  [[ -f "${OCP_SSH_KEY}" ]] || ocp_die "SSH key not found: ${OCP_SSH_KEY}"
  chmod 600 "${OCP_SSH_KEY}"
  touch "${OCP_KNOWN_HOSTS}"
  chmod 600 "${OCP_KNOWN_HOSTS}"

  OCP_SSH_OPTS=(
    -i "${OCP_SSH_KEY}"
    -o IdentitiesOnly=yes
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="${OCP_KNOWN_HOSTS}"
    -o ConnectTimeout=8
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=8
  )
  OCP_JUMP="${OCP_SSH_USER}@${OCP_JUMP_SSH_IP}"
}

ocp_ssh() {
  ssh "${OCP_SSH_OPTS[@]}" "${OCP_JUMP}" "$@"
}

# ocp_put <local file> <remote path> [mode]
ocp_put() {
  local src="$1" dst="$2" mode="${3:-600}"
  ocp_ssh "mkdir -p $(printf '%q' "$(dirname "${dst}")") && umask 077 && cat > $(printf '%q' "${dst}") && chmod ${mode} $(printf '%q' "${dst}")" <"${src}"
}

# ocp_get <remote path> <local file>
ocp_get() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "${dst}")"
  (umask 077 && ocp_ssh "cat $(printf '%q' "${src}")" >"${dst}")
}

# ocp_remote <remote/script.sh> [KEY=VAL ...]
# Streams a repo script to bash on the jump host (nothing is copied). The
# common OCP_* paths are always passed; extra KEY=VAL pairs are added.
ocp_remote() {
  local script="${OCP_SCRIPT_DIR}/remote/$1"
  shift
  local remote="env" pair
  [[ -f "${script}" ]] || ocp_die "Missing remote script: ${script}"
  for pair in \
    "OCP_CLUSTER_NAME=${OCP_CLUSTER_NAME}" \
    "OCP_CLOUD=${OCP_CLOUD}" \
    "OCP_WORK=${OCP_REMOTE_WORK}" \
    "OCP_INSTALL=${OCP_REMOTE_INSTALL}" \
    "OCP_RELEASE=${OCP_RELEASE}" \
    "$@"; do
    remote+=" ${pair%%=*}=$(printf '%q' "${pair#*=}")"
  done
  remote+=" bash -s"
  ssh "${OCP_SSH_OPTS[@]}" "${OCP_JUMP}" "${remote}" <"${script}"
}

ocp_wait_ssh() {
  local tries="${1:-60}" n=0
  ocp_step "waiting for SSH on ${OCP_JUMP}"
  until ocp_ssh true 2>/dev/null; do
    n=$((n + 1))
    if (( n >= tries )); then
      ocp_die "SSH to ${OCP_JUMP} did not come up (key ${OCP_SSH_KEY})"
    fi
    sleep 5
  done
}

ocp_phase_done() {
  [[ -f "${OCP_PHASE_DIR}/$1.done" ]]
}

ocp_phase_mark() {
  date -u +%Y-%m-%dT%H:%M:%SZ >"${OCP_PHASE_DIR}/$1.done"
}

ocp_phase_clear() {
  rm -f "${OCP_PHASE_DIR}/$1.done"
}
