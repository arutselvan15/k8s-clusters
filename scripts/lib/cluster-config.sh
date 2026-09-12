#!/usr/bin/env bash
# Resolve one cluster YAML and bind output paths. Source after paths.sh.
# Build is always one cluster: pass a config id or path (never a list).

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing cluster-config.sh}"

k8s_plat_cluster_token_ok() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# Usage: k8s_plat_resolve_cluster_config <aws|openstack> [id|path] [create]
# create=1 (default) copies default.yaml.example when spec is default and missing.
# Sets K8S_PLAT_CLUSTER_CONFIG and K8S_PLAT_CLUSTER_CONFIG_ID.
k8s_plat_resolve_cluster_config() {
  local platform="$1"
  local spec="${2:-default}"
  local create="${3:-1}"
  local dir="${K8S_PLAT_CONFIG_DIR}/${platform}/clusters"
  local example="${dir}/default.yaml.example"
  local resolved=""
  local dest=""

  mkdir -p "${dir}"

  if [[ "${spec}" == /* && -f "${spec}" ]]; then
    resolved="${spec}"
  elif [[ -f "${REPO_ROOT}/${spec}" ]]; then
    resolved="${REPO_ROOT}/${spec}"
  elif [[ -f "${spec}" ]]; then
    resolved="$(cd "$(dirname "${spec}")" && pwd)/$(basename "${spec}")"
  elif [[ -f "${dir}/${spec}" ]]; then
    resolved="${dir}/${spec}"
  elif [[ -f "${dir}/${spec}.yaml" ]]; then
    resolved="${dir}/${spec}.yaml"
  elif [[ "${spec}" == "default" && "${create}" == "1" && -f "${example}" ]]; then
    dest="${dir}/default.yaml"
    cp "${example}" "${dest}"
    echo "==> Wrote ${dest} from default.yaml.example"
    resolved="${dest}"
  else
    echo "No cluster config for ${platform}: ${spec}" >&2
    echo "  cp ${example} ${dir}/${spec%.yaml}.yaml" >&2
    echo "  ./scripts/infra/up.sh ${platform} ${spec%.yaml}" >&2
    return 1
  fi

  K8S_PLAT_CLUSTER_CONFIG="${resolved}"
  K8S_PLAT_CLUSTER_CONFIG_ID="$(basename "${resolved}")"
  K8S_PLAT_CLUSTER_CONFIG_ID="${K8S_PLAT_CLUSTER_CONFIG_ID%.yaml}"
}

# Read identity from K8S_PLAT_CLUSTER_CONFIG and set clusters/<cluster_name>/ paths.
k8s_plat_apply_cluster_outputs() {
  local name cp_prefix wk_prefix
  local yaml="${K8S_PLAT_CLUSTER_CONFIG:?cluster config not resolved}"

  name="$(k8s_plat_yaml_get "${yaml}" cluster_name 2>/dev/null || true)"
  if [[ -z "${name}" ]]; then
    echo "Set cluster_name in ${yaml}" >&2
    return 1
  fi
  if ! k8s_plat_cluster_token_ok "${name}"; then
    echo "cluster_name must be a simple name (letters, digits, . _ -): ${name}" >&2
    return 1
  fi

  cp_prefix="$(k8s_plat_yaml_get "${yaml}" control_plane_prefix 2>/dev/null || echo "cp")"
  wk_prefix="$(k8s_plat_yaml_get "${yaml}" worker_prefix 2>/dev/null || echo "wk")"
  if ! k8s_plat_cluster_token_ok "${cp_prefix}"; then
    echo "control_plane_prefix must be a simple name: ${cp_prefix}" >&2
    return 1
  fi
  if ! k8s_plat_cluster_token_ok "${wk_prefix}"; then
    echo "worker_prefix must be a simple name: ${wk_prefix}" >&2
    return 1
  fi

  K8S_PLAT_CLUSTER_NAME="${name}"
  K8S_PLAT_CONTROL_PLANE_PREFIX="${cp_prefix}"
  K8S_PLAT_WORKER_PREFIX="${wk_prefix}"
  K8S_PLAT_CLUSTER_DIR="${K8S_PLAT_CLUSTERS_DIR}/${name}"
  K8S_PLAT_CLUSTER_KUBECONFIG="${K8S_PLAT_CLUSTER_DIR}/kubeconfig"
  K8S_PLAT_CLUSTER_SSH_KEY="${K8S_PLAT_CLUSTER_DIR}/ssh.pem"
  K8S_PLAT_CLUSTER_ENV="${K8S_PLAT_CLUSTER_DIR}/cluster.env"
  K8S_PLAT_CLUSTER_KNOWN_HOSTS="${K8S_PLAT_CLUSTER_DIR}/known_hosts"
  K8S_PLAT_TFSTATE="${K8S_PLAT_CLUSTER_DIR}/terraform.tfstate"

  # Bind former aws/os path names so existing scripts keep working.
  K8S_PLAT_AWS_CLUSTER_DIR="${K8S_PLAT_CLUSTER_DIR}"
  K8S_PLAT_AWS_KUBECONFIG="${K8S_PLAT_CLUSTER_KUBECONFIG}"
  K8S_PLAT_AWS_SSH_KEY="${K8S_PLAT_CLUSTER_SSH_KEY}"
  K8S_PLAT_AWS_CLUSTER_ENV="${K8S_PLAT_CLUSTER_ENV}"
  K8S_PLAT_AWS_KNOWN_HOSTS="${K8S_PLAT_CLUSTER_KNOWN_HOSTS}"
  K8S_PLAT_AWS_INFRA_YAML="${yaml}"

  K8S_PLAT_OS_CLUSTER_DIR="${K8S_PLAT_CLUSTER_DIR}"
  K8S_PLAT_OS_KUBECONFIG="${K8S_PLAT_CLUSTER_KUBECONFIG}"
  K8S_PLAT_OS_SSH_KEY="${K8S_PLAT_CLUSTER_SSH_KEY}"
  K8S_PLAT_OS_CLUSTER_ENV="${K8S_PLAT_CLUSTER_ENV}"
  K8S_PLAT_OS_KNOWN_HOSTS="${K8S_PLAT_CLUSTER_KNOWN_HOSTS}"
  K8S_PLAT_OS_INFRA_YAML="${yaml}"
  K8S_OS_CONFIG_FILE="${yaml}"
  export K8S_OS_CONFIG_FILE

  mkdir -p "${K8S_PLAT_CLUSTER_DIR}"
  echo "==> Cluster ${K8S_PLAT_CLUSTER_NAME} (config ${yaml})"
  echo "    nodes ${K8S_PLAT_CLUSTER_NAME}-${K8S_PLAT_CONTROL_PLANE_PREFIX} / ${K8S_PLAT_CLUSTER_NAME}-${K8S_PLAT_WORKER_PREFIX}-N"
  echo "    outputs ${K8S_PLAT_CLUSTER_DIR}"
}

k8s_plat_terraform_init() {
  local env_dir="$1"
  local legacy="${env_dir}/terraform.tfstate"
  mkdir -p "${K8S_PLAT_CLUSTER_DIR}"
  if [[ -f "${legacy}" && ! -f "${K8S_PLAT_TFSTATE}" ]]; then
    mv "${legacy}" "${K8S_PLAT_TFSTATE}"
    echo "==> Moved Terraform state to ${K8S_PLAT_TFSTATE}"
    if [[ -f "${legacy}.backup" && ! -f "${K8S_PLAT_TFSTATE}.backup" ]]; then
      mv "${legacy}.backup" "${K8S_PLAT_TFSTATE}.backup"
    fi
  fi
  terraform init -input=false -reconfigure -backend-config="path=${K8S_PLAT_TFSTATE}"
}

# kubeadm: cluster id, yaml path, or clusters/<name>/cluster.env
k8s_plat_resolve_kubeadm_inventory() {
  local spec="${1:-}"
  local env=""
  local platform=""

  if [[ -z "${spec}" ]]; then
    echo "Pass a cluster config (example: default) or -i clusters/<name>/cluster.env" >&2
    return 1
  fi

  if [[ "${spec}" == /* && -f "${spec}" ]]; then
    if [[ "${spec}" == *.env ]]; then
      K8S_PLAT_KUBEADM_INVENTORY="${spec}"
      return 0
    fi
    if [[ "${spec}" == *.yaml ]]; then
      K8S_PLAT_CLUSTER_CONFIG="${spec}"
      k8s_plat_apply_cluster_outputs
      if [[ -f "${K8S_PLAT_CLUSTER_ENV}" ]]; then
        K8S_PLAT_KUBEADM_INVENTORY="${K8S_PLAT_CLUSTER_ENV}"
        return 0
      fi
    fi
  elif [[ -f "${REPO_ROOT}/${spec}" && "${spec}" == *.env ]]; then
    K8S_PLAT_KUBEADM_INVENTORY="${REPO_ROOT}/${spec}"
    return 0
  elif [[ -f "${REPO_ROOT}/${spec}" && "${spec}" == *.yaml ]]; then
    K8S_PLAT_CLUSTER_CONFIG="${REPO_ROOT}/${spec}"
    k8s_plat_apply_cluster_outputs
    if [[ -f "${K8S_PLAT_CLUSTER_ENV}" ]]; then
      K8S_PLAT_KUBEADM_INVENTORY="${K8S_PLAT_CLUSTER_ENV}"
      return 0
    fi
  elif [[ -f "${K8S_PLAT_CLUSTERS_DIR}/${spec}/cluster.env" ]]; then
    K8S_PLAT_KUBEADM_INVENTORY="${K8S_PLAT_CLUSTERS_DIR}/${spec}/cluster.env"
    return 0
  fi

  for platform in aws openstack; do
    if k8s_plat_resolve_cluster_config "${platform}" "${spec}" 0 2>/dev/null; then
      k8s_plat_apply_cluster_outputs
      env="${K8S_PLAT_CLUSTER_ENV}"
      if [[ -f "${env}" ]]; then
        K8S_PLAT_KUBEADM_INVENTORY="${env}"
        return 0
      fi
    fi
  done

  echo "No kubeadm inventory for ${spec}." >&2
  echo "Run Day 0 first: ./scripts/infra/up.sh aws|openstack ${spec}" >&2
  return 1
}
