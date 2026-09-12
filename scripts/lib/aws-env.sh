#!/usr/bin/env bash
# Source from aws/up.sh and aws/down.sh. Points AWS CLI and Terraform at
# k8s-platform/.aws (not ~/.aws). Requires REPO_ROOT.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing aws-env.sh}"

export AWS_SHARED_CREDENTIALS_FILE="${REPO_ROOT}/.aws/credentials"
export AWS_CONFIG_FILE="${REPO_ROOT}/.aws/config"
export AWS_SDK_LOAD_CONFIG=1
export AWS_PROFILE="${AWS_PROFILE:-default}"

k8s_plat_load_provider_vars() {
  local region cluster_name vpc_cidr admin_cidr node_instance_type worker_nodes
  region="$(k8s_plat_aws_config_get region 2>/dev/null || echo "us-east-1")"
  cluster_name="$(k8s_plat_aws_config_get cluster_name 2>/dev/null || echo "k8s-aws")"
  vpc_cidr="$(k8s_plat_aws_config_get vpc_cidr 2>/dev/null || echo "10.0.0.0/16")"
  admin_cidr="$(k8s_plat_aws_config_get admin_cidr 2>/dev/null || echo "0.0.0.0/0")"
  node_instance_type="$(k8s_plat_aws_config_get node_instance_type 2>/dev/null || echo "t3.medium")"
  worker_nodes="$(k8s_plat_aws_config_get worker_nodes 2>/dev/null || echo "1")"
  echo "==> AWS provider from ${AWS_CONFIG_FILE}: region=${region} profile=${AWS_PROFILE}"
  echo "    cluster_name=${cluster_name} vpc_cidr=${vpc_cidr} admin_cidr=${admin_cidr}"
  echo "    node_instance_type=${node_instance_type} worker_nodes=${worker_nodes}"
  K8S_TF_VAR_ARGS=(
    -var "aws_region=${region}"
    -var "aws_profile=${AWS_PROFILE}"
    -var "cluster_name=${cluster_name}"
    -var "vpc_cidr=${vpc_cidr}"
    -var "admin_cidr=${admin_cidr}"
    -var "node_instance_type=${node_instance_type}"
    -var "worker_nodes=${worker_nodes}"
  )
}

k8s_plat_aws_config_get() {
  local key="$1"
  python3 - "$key" <<'PY'
import configparser, os, sys

key = sys.argv[1]
path = os.environ["AWS_CONFIG_FILE"]
profile = os.environ.get("AWS_PROFILE", "default")
cfg = configparser.RawConfigParser()
if not cfg.read(path):
    sys.exit(1)

if profile == "default":
    section = "default" if cfg.has_section("default") else "DEFAULT"
else:
    section = f"profile {profile}"
    if not cfg.has_section(section) and cfg.has_section(profile):
        section = profile

if not cfg.has_section(section) and section != "DEFAULT":
    sys.exit(1)
if not cfg.has_option(section, key):
    sys.exit(1)
value = cfg.get(section, key).strip().strip('"').strip("'")
if not value:
    sys.exit(1)
print(value)
PY
}

k8s_plat_require_aws_credentials() {
  mkdir -p "${REPO_ROOT}/.aws"

  if [[ ! -f "${AWS_SHARED_CREDENTIALS_FILE}" ]]; then
    if [[ -f "${HOME}/.aws/credentials" ]]; then
      cp "${HOME}/.aws/credentials" "${AWS_SHARED_CREDENTIALS_FILE}"
      chmod 600 "${AWS_SHARED_CREDENTIALS_FILE}"
      echo "==> Copied ~/.aws/credentials -> ${AWS_SHARED_CREDENTIALS_FILE} (gitignored)"
    else
      echo "Missing ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      echo "Copy ${REPO_ROOT}/.aws/credentials.example to credentials and fill in keys." >&2
      echo "  cp ${REPO_ROOT}/.aws/credentials.example ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      echo "  chmod 600 ${AWS_SHARED_CREDENTIALS_FILE}" >&2
      return 1
    fi
  fi
  chmod 600 "${AWS_SHARED_CREDENTIALS_FILE}"

  if [[ ! -f "${AWS_CONFIG_FILE}" ]]; then
    cp "${REPO_ROOT}/.aws/config.example" "${AWS_CONFIG_FILE}"
    echo "==> Wrote ${AWS_CONFIG_FILE} from config.example"
  fi
}
