#!/usr/bin/env bash
# Day 0 — destroy EC2 kubeadm lab. Independent of Kind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_DIR="${REPO_ROOT}/infra/terraform/environments/ec2"
AUTO_APPROVE=""
CLUSTER_SPEC="default"
K8S_TF_VAR_ARGS=()

# shellcheck source=scripts/lib/aws-env.sh
source "$REPO_ROOT/scripts/lib/aws-env.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/aws/down.sh [cluster] [-y]

Destroy the AWS EC2 lab for one cluster config.
Does not delete anything outside this cluster's Terraform state.
  -y, --yes   terraform destroy -auto-approve
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -y | --yes)
      AUTO_APPROVE="-auto-approve"
      ;;
    -c | --cluster)
      CLUSTER_SPEC="${2:?cluster config required}"
      shift
      ;;
    *)
      CLUSTER_SPEC="$1"
      ;;
  esac
  shift
done

if [[ ! -d "$ENV_DIR" ]]; then
  echo "Terraform environment not found: $ENV_DIR" >&2
  exit 1
fi

k8s_plat_resolve_cluster_config aws "${CLUSTER_SPEC}" 0
k8s_plat_apply_cluster_outputs

if [[ ! -f "${K8S_PLAT_TFSTATE}" && ! -d "${ENV_DIR}/.terraform" ]]; then
  echo "No Terraform state for cluster ${K8S_PLAT_CLUSTER_NAME}; nothing to destroy."
  exit 0
fi

echo "==> Destroy AWS cluster ${K8S_PLAT_CLUSTER_NAME}: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform aws
k8s_plat_require_aws_credentials
k8s_plat_load_provider_vars

cd "$ENV_DIR"
k8s_plat_terraform_init "$ENV_DIR"
# shellcheck disable=SC2086
terraform destroy -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

if [[ -d "${K8S_PLAT_CLUSTER_DIR}" ]]; then
  rm -f "${K8S_PLAT_CLUSTER_KUBECONFIG}" "${K8S_PLAT_CLUSTER_ENV}" "${K8S_PLAT_CLUSTER_KNOWN_HOSTS}"
  echo "Removed local kubeconfig/inventory under ${K8S_PLAT_CLUSTER_DIR}"
fi

echo "AWS cluster ${K8S_PLAT_CLUSTER_NAME} destroyed."
