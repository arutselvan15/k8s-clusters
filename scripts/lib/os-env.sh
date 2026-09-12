#!/usr/bin/env bash
# Source from openstack/up.sh and openstack/down.sh.
# Points Terraform at k8s-platform/.openstack/clouds.yaml. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing os-env.sh}"

export OS_CLIENT_CONFIG_FILE="${REPO_ROOT}/.openstack/clouds.yaml"
export K8S_OS_CONFIG_FILE="${REPO_ROOT}/.openstack/config"
export OS_CLOUD="${OS_CLOUD:-lab}"

k8s_plat_os_config_get() {
  local key="$1"
  python3 - "$key" <<'PY'
import configparser, os, sys

key = sys.argv[1]
path = os.environ["K8S_OS_CONFIG_FILE"]
cfg = configparser.RawConfigParser()
if not cfg.read(path):
    sys.exit(1)

section = "default" if cfg.has_section("default") else "DEFAULT"
if not cfg.has_option(section, key):
    sys.exit(1)
value = cfg.get(section, key).strip().strip('"').strip("'")
if not value:
    sys.exit(1)
print(value)
PY
}

k8s_plat_require_os_credentials() {
  mkdir -p "${REPO_ROOT}/.openstack"

  if [[ ! -f "${OS_CLIENT_CONFIG_FILE}" ]]; then
    if [[ -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
      cp "${HOME}/.config/openstack/clouds.yaml" "${OS_CLIENT_CONFIG_FILE}"
      chmod 600 "${OS_CLIENT_CONFIG_FILE}"
      echo "==> Copied ~/.config/openstack/clouds.yaml -> ${OS_CLIENT_CONFIG_FILE} (gitignored)"
    else
      echo "Missing ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "Copy clouds.yaml.example and fill in Keystone auth (never commit it)." >&2
      echo "  cp ${REPO_ROOT}/.openstack/clouds.yaml.example ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  chmod 600 ${OS_CLIENT_CONFIG_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${OS_CLIENT_CONFIG_FILE}"

  if [[ ! -f "${K8S_OS_CONFIG_FILE}" ]]; then
    cp "${REPO_ROOT}/.openstack/config.example" "${K8S_OS_CONFIG_FILE}"
    echo "==> Wrote ${K8S_OS_CONFIG_FILE} from config.example"
    echo "Edit image_name, node_flavor, and network_name for your cloud." >&2
    return 1
  fi
}

k8s_plat_load_os_provider_vars() {
  local cloud cluster_name admin_cidr network_name image_name
  local node_flavor worker_nodes ssh_user root_volume_gb availability_zone
  local missing=0
  local key=""
  local val=""

  OS_CLOUD="$(k8s_plat_os_config_get cloud 2>/dev/null || echo "${OS_CLOUD}")"
  export OS_CLOUD

  if k8s_plat_os_config_get network_name >/dev/null 2>&1; then
    network_name="$(k8s_plat_os_config_get network_name)"
  elif k8s_plat_os_config_get external_network >/dev/null 2>&1; then
    network_name="$(k8s_plat_os_config_get external_network)"
  else
    echo "Missing network_name in ${K8S_OS_CONFIG_FILE}" >&2
    missing=1
    network_name=""
  fi

  for key in image_name node_flavor; do
    if ! k8s_plat_os_config_get "$key" >/dev/null 2>&1; then
      echo "Missing ${key} in ${K8S_OS_CONFIG_FILE}" >&2
      missing=1
    else
      val="$(k8s_plat_os_config_get "$key")"
      if [[ "${val}" == "REPLACE_ME" ]]; then
        echo "Set ${key} in ${K8S_OS_CONFIG_FILE} (Horizon: Images / Flavors / Networks)." >&2
        missing=1
      fi
    fi
  done
  if [[ -n "${network_name}" && "${network_name}" == "REPLACE_ME" ]]; then
    echo "Set network_name in ${K8S_OS_CONFIG_FILE} to an existing Neutron network." >&2
    missing=1
  fi
  if [[ "${missing}" -ne 0 ]]; then
    echo "Copy ${REPO_ROOT}/.openstack/config.example and set cloud-specific names." >&2
    return 1
  fi

  cloud="${OS_CLOUD}"
  cluster_name="$(k8s_plat_os_config_get cluster_name 2>/dev/null || echo "k8s-os")"
  admin_cidr="$(k8s_plat_os_config_get admin_cidr 2>/dev/null || echo "0.0.0.0/0")"
  image_name="$(k8s_plat_os_config_get image_name)"
  node_flavor="$(k8s_plat_os_config_get node_flavor)"
  worker_nodes="$(k8s_plat_os_config_get worker_nodes 2>/dev/null || echo "1")"
  ssh_user="$(k8s_plat_os_config_get ssh_user 2>/dev/null || echo "ubuntu")"
  root_volume_gb="$(k8s_plat_os_config_get root_volume_gb 2>/dev/null || echo "20")"
  availability_zone="$(k8s_plat_os_config_get availability_zone 2>/dev/null || echo "")"

  echo "==> OpenStack from ${OS_CLIENT_CONFIG_FILE} cloud=${cloud}"
  echo "    cluster_name=${cluster_name} network_name=${network_name} admin_cidr=${admin_cidr}"
  echo "    image_name=${image_name} node_flavor=${node_flavor} worker_nodes=${worker_nodes}"
  echo "    ssh_user=${ssh_user}"

  K8S_TF_VAR_ARGS=(
    -var "cloud=${cloud}"
    -var "cluster_name=${cluster_name}"
    -var "admin_cidr=${admin_cidr}"
    -var "network_name=${network_name}"
    -var "image_name=${image_name}"
    -var "node_flavor=${node_flavor}"
    -var "worker_nodes=${worker_nodes}"
    -var "ssh_user=${ssh_user}"
    -var "root_volume_gb=${root_volume_gb}"
    -var "availability_zone=${availability_zone}"
  )
}
