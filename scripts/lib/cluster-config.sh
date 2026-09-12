#!/usr/bin/env bash
# Resolve one cluster YAML and bind output paths. Source after paths.sh.
# Build is always one cluster: pass a config id or path (never a list).

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing cluster-config.sh}"

k8s_plat_cluster_token_ok() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# Usage: k8s_plat_resolve_cluster_config <kind|aws|openstack> [id|path]
# Sets K8S_PLAT_CLUSTER_CONFIG from clusters/<platform>/<id>/config.yaml
k8s_plat_cluster_yaml_in_dir() {
  local d="$1"
  if [[ -f "${d}/config.yaml" ]]; then
    echo "${d}/config.yaml"
    return 0
  fi
  return 1
}

k8s_plat_list_cluster_ids() {
  local platform="$1"
  local dir="${K8S_PLAT_CLUSTER_INPUT_DIR}/${platform}"
  local d yaml
  [[ -d "${dir}" ]] || return 0
  for d in "${dir}"/*; do
    [[ -d "${d}" ]] || continue
    yaml="$(k8s_plat_cluster_yaml_in_dir "${d}" 2>/dev/null || true)"
    if [[ -n "${yaml}" ]]; then
      basename "${d}"
    fi
  done
}

k8s_plat_require_cluster_spec() {
  local platform="$1"
  local spec="$2"
  local ids
  if [[ -n "${spec}" ]]; then
    return 0
  fi
  echo "Pass a cluster id: ./scripts/infra/up.sh ${platform} <id>" >&2
  ids="$(k8s_plat_list_cluster_ids "${platform}")"
  if [[ -n "${ids}" ]]; then
    echo "Available under clusters/${platform}/:" >&2
    echo "${ids}" | sed 's/^/  /' >&2
  else
    echo "  Add clusters/${platform}/<id>/config.yaml" >&2
  fi
  return 1
}

# If spec is empty and the platform has exactly one config dir, use it.
k8s_plat_effective_cluster_spec() {
  local platform="$1"
  local spec="${2:-}"
  local ids
  local count
  if [[ -n "${spec}" ]]; then
    printf '%s' "${spec}"
    return 0
  fi
  ids="$(k8s_plat_list_cluster_ids "${platform}")"
  if [[ -z "${ids}" ]]; then
    k8s_plat_require_cluster_spec "${platform}" ""
    return 1
  fi
  count="$(printf '%s\n' "${ids}" | grep -c .)"
  if [[ "${count}" == "1" ]]; then
    echo "==> Using clusters/${platform}/${ids}" >&2
    printf '%s' "${ids}"
    return 0
  fi
  k8s_plat_require_cluster_spec "${platform}" ""
  return 1
}

k8s_plat_resolve_cluster_config() {
  local platform="$1"
  local spec="${2:-}"
  local dir="${K8S_PLAT_CLUSTER_INPUT_DIR}/${platform}"
  local resolved=""
  local yaml=""

  k8s_plat_migrate_to_sensitive
  k8s_plat_require_cluster_spec "${platform}" "${spec}" || return 1

  if [[ "${spec}" == /* && -f "${spec}" ]]; then
    resolved="${spec}"
  elif [[ -f "${REPO_ROOT}/${spec}" ]]; then
    resolved="${REPO_ROOT}/${spec}"
  elif [[ -f "${spec}" ]]; then
    resolved="$(cd "$(dirname "${spec}")" && pwd)/$(basename "${spec}")"
  elif yaml="$(k8s_plat_cluster_yaml_in_dir "${dir}/${spec}")"; then
    resolved="${yaml}"
  else
    echo "No cluster config for ${platform}: ${spec}" >&2
    echo "  Add ${dir}/${spec}/config.yaml" >&2
    echo "  ./scripts/infra/up.sh ${platform} ${spec}" >&2
    return 1
  fi

  K8S_PLAT_CLUSTER_CONFIG="${resolved}"
  K8S_PLAT_CLUSTER_PLATFORM="${platform}"
  if [[ "$(basename "${resolved}")" == "config.yaml" ]]; then
    K8S_PLAT_CLUSTER_CONFIG_ID="$(basename "$(dirname "${resolved}")")"
  else
    K8S_PLAT_CLUSTER_CONFIG_ID="$(basename "${resolved}")"
    K8S_PLAT_CLUSTER_CONFIG_ID="${K8S_PLAT_CLUSTER_CONFIG_ID%.yaml}"
  fi
}

# Read identity from K8S_PLAT_CLUSTER_CONFIG and set sensitive/<env>/<cluster_name>/ paths.
k8s_plat_apply_cluster_outputs() {
  local name platform
  local yaml="${K8S_PLAT_CLUSTER_CONFIG:?cluster config not resolved}"

  case "${yaml}" in
    */clusters/aws/*) platform="aws" ;;
    */clusters/openstack/*) platform="openstack" ;;
    */clusters/kind/*) platform="kind" ;;
    *) platform="${K8S_PLAT_CLUSTER_PLATFORM:-}" ;;
  esac
  if [[ -z "${platform}" ]]; then
    echo "Cannot tell kind vs aws vs openstack for ${yaml}" >&2
    return 1
  fi
  K8S_PLAT_CLUSTER_PLATFORM="${platform}"

  name="$(k8s_plat_yaml_get "${yaml}" cluster_name 2>/dev/null || true)"
  if [[ -z "${name}" ]]; then
    name="${K8S_PLAT_CLUSTER_CONFIG_ID:-}"
  fi
  if [[ -z "${name}" ]]; then
    echo "Set cluster_name in ${yaml}" >&2
    return 1
  fi
  if ! k8s_plat_cluster_token_ok "${name}"; then
    echo "cluster_name must be a simple name (letters, digits, . _ -): ${name}" >&2
    return 1
  fi

  K8S_PLAT_CLUSTER_NAME="${name}"
  K8S_PLAT_CLUSTER_DIR="${K8S_PLAT_SENSITIVE_DIR}/${platform}/${name}"
  K8S_PLAT_CLUSTER_KUBECONFIG="${K8S_PLAT_CLUSTER_DIR}/kubeconfig"
  K8S_PLAT_TFSTATE="${K8S_PLAT_CLUSTER_DIR}/terraform.tfstate"

  if [[ "${platform}" == "kind" ]]; then
    k8s_plat_migrate_kind_flat_outputs "${name}"
    K8S_PLAT_CLUSTER_SSH_KEY=""
    K8S_PLAT_CLUSTER_ENV=""
    K8S_PLAT_CLUSTER_KNOWN_HOSTS=""
    mkdir -p "${K8S_PLAT_CLUSTER_DIR}"
    echo "==> Cluster ${K8S_PLAT_CLUSTER_NAME} (config ${yaml})"
    echo "    outputs ${K8S_PLAT_CLUSTER_DIR}"
    return 0
  fi

  K8S_PLAT_CLUSTER_SSH_KEY="${K8S_PLAT_CLUSTER_DIR}/ssh.pem"
  K8S_PLAT_CLUSTER_ENV="${K8S_PLAT_CLUSTER_DIR}/cluster.env"
  K8S_PLAT_CLUSTER_KNOWN_HOSTS="${K8S_PLAT_CLUSTER_DIR}/known_hosts"

  mkdir -p "${K8S_PLAT_CLUSTER_DIR}"
  echo "==> Cluster ${K8S_PLAT_CLUSTER_NAME} (config ${yaml})"
  echo "    nodes ${K8S_PLAT_CLUSTER_NAME}-cp / ${K8S_PLAT_CLUSTER_NAME}-wk-N"
  echo "    outputs ${K8S_PLAT_CLUSTER_DIR}"
}

# leftover: sensitive/kind/{kubeconfig,tfstate} -> sensitive/kind/<cluster_name>/
k8s_plat_migrate_kind_flat_outputs() {
  local name="$1"
  local plat="${K8S_PLAT_KIND_DIR:-${K8S_PLAT_SENSITIVE_DIR}/kind}"
  local dest="${plat}/${name}"
  local f
  [[ -d "${plat}" ]] || return 0
  for f in kubeconfig terraform.tfstate terraform.tfstate.backup; do
    if [[ -f "${plat}/${f}" && ! -e "${dest}/${f}" ]]; then
      mkdir -p "${dest}"
      mv "${plat}/${f}" "${dest}/${f}"
      echo "==> Moved ${plat}/${f} -> ${dest}/${f}"
    fi
  done
}

# After terraform destroy succeeds (or there is nothing left to destroy):
# remove this cluster's outputs. Do not archive locally — S3 (and bucket
# versioning) is the backup. Never touches aws/credentials, cli.conf, or
# openstack/clouds.yaml.
k8s_plat_purge_cluster_outputs() {
  local dir="${K8S_PLAT_CLUSTER_DIR:?cluster dir not set}"
  local f
  [[ -d "${dir}" ]] || return 0
  for f in \
    "${K8S_PLAT_CLUSTER_KUBECONFIG:-}" \
    "${K8S_PLAT_CLUSTER_ENV:-}" \
    "${K8S_PLAT_CLUSTER_KNOWN_HOSTS:-}" \
    "${K8S_PLAT_CLUSTER_SSH_KEY:-}" \
    "${K8S_PLAT_TFSTATE:-}" \
    "${K8S_PLAT_TFSTATE:-}.backup"; do
    [[ -n "${f}" && "${f}" != ".backup" && -e "${f}" ]] || continue
    rm -f "${f}"
  done
  if [[ -d "${dir}" && -z "$(ls -A "${dir}" 2>/dev/null)" ]]; then
    rmdir "${dir}"
    echo "==> Removed ${dir}"
  else
    echo "==> Cleared cluster outputs under ${dir}"
  fi
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

# Same args as infra/up.sh and infra/down.sh: <aws|openstack> <cluster-id>
k8s_plat_bind_kubeadm_inventory() {
  local platform="$1"
  local spec="$2"

  case "${platform}" in
    aws | openstack) ;;
    *)
      echo "Pass aws or openstack (same as ./scripts/infra/up.sh)." >&2
      return 1
      ;;
  esac
  k8s_plat_resolve_cluster_config "${platform}" "${spec}" || return 1
  k8s_plat_apply_cluster_outputs
  if [[ ! -f "${K8S_PLAT_CLUSTER_ENV}" ]]; then
    echo "Inventory not found: ${K8S_PLAT_CLUSTER_ENV}" >&2
    echo "Run ./scripts/infra/up.sh ${platform} ${spec} first." >&2
    return 1
  fi
}
