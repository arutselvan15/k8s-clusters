#!/usr/bin/env bash
# Source from aws/up.sh and aws/down.sh. Points AWS CLI and Terraform at
# config/aws (not ~/.aws). Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing aws-env.sh}"

# shellcheck source=scripts/lib/paths.sh
source "${REPO_ROOT}/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/cluster-config.sh
source "${REPO_ROOT}/scripts/lib/cluster-config.sh"

export AWS_SHARED_CREDENTIALS_FILE="${K8S_PLAT_AWS_CREDENTIALS}"
export AWS_CONFIG_FILE="${K8S_PLAT_AWS_CLI_CONF}"
export AWS_SDK_LOAD_CONFIG=1
export AWS_PROFILE="${AWS_PROFILE:-default}"

k8s_plat_aws_infra_get() {
  k8s_plat_yaml_get "${K8S_PLAT_AWS_INFRA_YAML}" "$1"
}

k8s_plat_aws_cli_get() {
  local profile="${AWS_PROFILE}"
  local section="default"
  if [[ "${profile}" != "default" ]]; then
    section="profile ${profile}"
  fi
  k8s_plat_ini_get "${K8S_PLAT_AWS_CLI_CONF}" "$1" "${section}" 2>/dev/null \
    || k8s_plat_ini_get "${K8S_PLAT_AWS_CLI_CONF}" "$1" "${profile}" 2>/dev/null \
    || k8s_plat_ini_get "${K8S_PLAT_AWS_CLI_CONF}" "$1" "default"
}

k8s_plat_load_provider_vars() {
  local region cluster_name vpc_cidr admin_cidr node_instance_type worker_nodes
  region="$(k8s_plat_aws_cli_get region 2>/dev/null || echo "us-east-1")"
  cluster_name="${K8S_PLAT_CLUSTER_NAME:-$(k8s_plat_aws_infra_get cluster_name 2>/dev/null || echo "k8s-aws")}"
  vpc_cidr="$(k8s_plat_aws_infra_get vpc_cidr 2>/dev/null || echo "10.0.0.0/16")"
  admin_cidr="$(k8s_plat_aws_infra_get admin_cidr 2>/dev/null || echo "0.0.0.0/0")"
  node_instance_type="$(k8s_plat_aws_infra_get node_instance_type 2>/dev/null || echo "t3.medium")"
  worker_nodes="$(k8s_plat_aws_infra_get worker_nodes 2>/dev/null || echo "1")"
  echo "==> AWS provider from ${AWS_CONFIG_FILE}: region=${region} profile=${AWS_PROFILE}"
  echo "    cluster_name=${cluster_name} vpc_cidr=${vpc_cidr} admin_cidr=${admin_cidr}"
  echo "    node_instance_type=${node_instance_type} worker_nodes=${worker_nodes}"
  echo "    prefixes ${K8S_PLAT_CONTROL_PLANE_PREFIX:-cp} / ${K8S_PLAT_WORKER_PREFIX:-wk}"
  echo "    cluster config=${K8S_PLAT_AWS_INFRA_YAML}"
  K8S_TF_VAR_ARGS=(
    -var "aws_region=${region}"
    -var "aws_profile=${AWS_PROFILE}"
    -var "cluster_name=${cluster_name}"
    -var "control_plane_prefix=${K8S_PLAT_CONTROL_PLANE_PREFIX:-cp}"
    -var "worker_prefix=${K8S_PLAT_WORKER_PREFIX:-wk}"
    -var "ssh_private_key_path=${K8S_PLAT_CLUSTER_SSH_KEY}"
    -var "vpc_cidr=${vpc_cidr}"
    -var "admin_cidr=${admin_cidr}"
    -var "node_instance_type=${node_instance_type}"
    -var "worker_nodes=${worker_nodes}"
  )
}

k8s_plat_require_aws_credentials() {
  mkdir -p "${K8S_PLAT_CONFIG_DIR}/aws" "${K8S_PLAT_CONFIG_DIR}/aws/clusters"

  if [[ ! -f "${AWS_SHARED_CREDENTIALS_FILE}" ]]; then
    if [[ -f "${REPO_ROOT}/.aws/credentials" ]]; then
      cp "${REPO_ROOT}/.aws/credentials" "${AWS_SHARED_CREDENTIALS_FILE}"
      chmod 600 "${AWS_SHARED_CREDENTIALS_FILE}"
      echo "==> Migrated .aws/credentials -> ${AWS_SHARED_CREDENTIALS_FILE}"
    elif [[ -f "${HOME}/.aws/credentials" ]]; then
      cp "${HOME}/.aws/credentials" "${AWS_SHARED_CREDENTIALS_FILE}"
      chmod 600 "${AWS_SHARED_CREDENTIALS_FILE}"
      echo "==> Copied ~/.aws/credentials -> ${AWS_SHARED_CREDENTIALS_FILE} (gitignored)"
    else
      echo "Missing ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      echo "  cp ${K8S_PLAT_CONFIG_DIR}/aws/credentials.example ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      echo "  chmod 600 ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${AWS_SHARED_CREDENTIALS_FILE}"

  if [[ ! -f "${AWS_CONFIG_FILE}" ]]; then
    if [[ -f "${REPO_ROOT}/.aws/config" ]]; then
      echo "==> Found legacy .aws/config. Copy region into ${AWS_CONFIG_FILE} (cli.conf.example)." >&2
    fi
    cp "${K8S_PLAT_CONFIG_DIR}/aws/cli.conf.example" "${AWS_CONFIG_FILE}"
    echo "==> Wrote ${AWS_CONFIG_FILE} from cli.conf.example"
  fi

}
