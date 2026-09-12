#!/usr/bin/env bash
# Source from openstack/up.sh and openstack/down.sh.
# Points Terraform at sensitive/openstack/clouds.yaml. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing os-env.sh}"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

export OS_CLIENT_CONFIG_FILE="${K8S_PLAT_OS_CLOUDS}"
export K8S_OS_CONFIG_FILE="${K8S_PLAT_OS_INFRA_YAML}"
export OS_CLOUD="${OS_CLOUD:-lab}"

k8s_plat_os_config_get() {
  k8s_plat_yaml_get "${K8S_OS_CONFIG_FILE}" "$1"
}

k8s_plat_require_os_credentials() {
  k8s_plat_migrate_to_sensitive
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}/openstack"

  if [[ ! -f "${OS_CLIENT_CONFIG_FILE}" ]]; then
    if [[ -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
      cp "${HOME}/.config/openstack/clouds.yaml" "${OS_CLIENT_CONFIG_FILE}"
      chmod 600 "${OS_CLIENT_CONFIG_FILE}"
      echo "==> Copied ~/.config/openstack/clouds.yaml -> ${OS_CLIENT_CONFIG_FILE} (gitignored)"
    else
      echo "Missing ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  cp ${K8S_PLAT_CLUSTER_INPUT_DIR}/openstack/clouds.yaml.example ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  chmod 600 ${OS_CLIENT_CONFIG_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${OS_CLIENT_CONFIG_FILE}"

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
    echo "Set image_name, node_flavor, and network_name in clusters/openstack/<id>/config.yaml." >&2
    return 1
  fi

  cloud="${OS_CLOUD}"
  cluster_name="${K8S_PLAT_CLUSTER_NAME:?cluster_name not set; pass a cluster id to up.sh}"
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
  echo "    nodes ${cluster_name}-cp / ${cluster_name}-wk-N"
  echo "    ssh_user=${ssh_user}"
  echo "    cluster config=${K8S_OS_CONFIG_FILE}"

  K8S_TF_VAR_ARGS=(
    -var "cloud=${cloud}"
    -var "cluster_name=${cluster_name}"
    -var "ssh_private_key_path=${K8S_PLAT_CLUSTER_SSH_KEY}"
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
