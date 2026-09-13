#!/usr/bin/env bash
# Source from openstack/up.sh and openstack/down.sh.
# Points Terraform at sensitive/openstack/clouds.yaml. Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing os-env.sh}"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

export OS_CLIENT_CONFIG_FILE="${K8S_PLAT_OS_CLOUDS}"

k8s_plat_require_os_credentials() {
  mkdir -p "${K8S_PLAT_SENSITIVE_DIR}/openstack"

  if [[ ! -f "${OS_CLIENT_CONFIG_FILE}" ]]; then
    if [[ -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
      cp "${HOME}/.config/openstack/clouds.yaml" "${OS_CLIENT_CONFIG_FILE}"
      chmod 600 "${OS_CLIENT_CONFIG_FILE}"
      echo "==> Copied ~/.config/openstack/clouds.yaml -> ${OS_CLIENT_CONFIG_FILE} (gitignored)"
    else
      echo "Missing ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  cp ${K8S_PLAT_SENSITIVE_DIR}/openstack/clouds.yaml.example ${OS_CLIENT_CONFIG_FILE}" >&2
      echo "  chmod 600 ${OS_CLIENT_CONFIG_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${OS_CLIENT_CONFIG_FILE}"
}

k8s_plat_os_reject_placeholder() {
  local key="$1"
  local val="$2"
  if [[ "${val}" == "REPLACE_ME" ]]; then
    echo "Set ${key} in ${K8S_PLAT_CLUSTER_CONFIG} (Horizon: Images / Flavors / Networks)." >&2
    return 1
  fi
}

k8s_plat_load_os_provider_vars() {
  local yaml="${K8S_PLAT_CLUSTER_CONFIG:?cluster config not resolved}"
  local cloud cluster_name admin_cidr network_name image_name
  local node_flavor worker_nodes ssh_user root_volume_gb availability_zone
  local ssh_port kube_port ssh_key_algorithm image_most_recent volume_delete

  cloud="$(k8s_plat_yaml_require "${yaml}" cloud)" || return 1
  export OS_CLOUD="${cloud}"

  cluster_name="${K8S_PLAT_CLUSTER_NAME:?cluster_name not set; pass a cluster id to up.sh}"
  admin_cidr="$(k8s_plat_yaml_require "${yaml}" admin_cidr)" || return 1
  ssh_port="$(k8s_plat_yaml_require "${yaml}" ssh_port)" || return 1
  kube_port="$(k8s_plat_yaml_require "${yaml}" kubernetes_api_port)" || return 1
  network_name="$(k8s_plat_yaml_require "${yaml}" network_name)" || return 1
  image_name="$(k8s_plat_yaml_require "${yaml}" image_name)" || return 1
  node_flavor="$(k8s_plat_yaml_require "${yaml}" node_flavor)" || return 1
  worker_nodes="$(k8s_plat_yaml_require "${yaml}" worker_nodes)" || return 1
  ssh_user="$(k8s_plat_yaml_require "${yaml}" ssh_user)" || return 1
  root_volume_gb="$(k8s_plat_yaml_require "${yaml}" root_volume_gb)" || return 1
  availability_zone="$(k8s_plat_yaml_require "${yaml}" availability_zone)" || return 1
  ssh_key_algorithm="$(k8s_plat_yaml_require "${yaml}" ssh_key_algorithm)" || return 1
  image_most_recent="$(k8s_plat_yaml_require "${yaml}" image_most_recent)" || return 1
  volume_delete="$(k8s_plat_yaml_require "${yaml}" volume_delete_on_termination)" || return 1

  k8s_plat_os_reject_placeholder image_name "${image_name}" || return 1
  k8s_plat_os_reject_placeholder node_flavor "${node_flavor}" || return 1
  k8s_plat_os_reject_placeholder network_name "${network_name}" || return 1

  echo "==> OpenStack from ${OS_CLIENT_CONFIG_FILE} cloud=${cloud}"
  echo "    cluster_name=${cluster_name} network_name=${network_name} admin_cidr=${admin_cidr}"
  echo "    image_name=${image_name} node_flavor=${node_flavor} worker_nodes=${worker_nodes}"
  echo "    nodes ${cluster_name}-cp / ${cluster_name}-wk-N"
  echo "    ssh_user=${ssh_user}"
  echo "    cluster config=${yaml}"

  K8S_TF_VAR_ARGS=(
    -var "cloud=${cloud}"
    -var "cluster_name=${cluster_name}"
    -var "ssh_private_key_path=${K8S_PLAT_CLUSTER_SSH_KEY}"
    -var "admin_cidr=${admin_cidr}"
    -var "ssh_port=${ssh_port}"
    -var "kubernetes_api_port=${kube_port}"
    -var "network_name=${network_name}"
    -var "image_name=${image_name}"
    -var "image_most_recent=${image_most_recent}"
    -var "node_flavor=${node_flavor}"
    -var "worker_nodes=${worker_nodes}"
    -var "ssh_user=${ssh_user}"
    -var "ssh_key_algorithm=${ssh_key_algorithm}"
    -var "root_volume_gb=${root_volume_gb}"
    -var "volume_delete_on_termination=${volume_delete}"
    -var "availability_zone=${availability_zone}"
  )
}
