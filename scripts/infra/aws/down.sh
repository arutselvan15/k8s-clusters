#!/usr/bin/env bash
# Day 0 — destroy EC2 kubeadm lab. Independent of Kind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_DIR="${REPO_ROOT}/infra/terraform/environments/ec2"
KUBECONFIG_FILE="${REPO_ROOT}/.kube/aws-dev.yaml"
INVENTORY_FILE="${REPO_ROOT}/.kube/aws-inventory.env"
AUTO_APPROVE=""
K8S_TF_VAR_ARGS=()

usage() {
  cat <<EOF
Usage: ./scripts/infra/aws/down.sh [-y]

Destroy the AWS EC2 lab (terraform environments/ec2).
Does not delete anything outside this Terraform state.
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
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -d "$ENV_DIR" ]]; then
  echo "Terraform environment not found: $ENV_DIR" >&2
  exit 1
fi

if [[ ! -d "${ENV_DIR}/.terraform" ]]; then
  echo "No Terraform state in ${ENV_DIR}; nothing to destroy."
  exit 0
fi

echo "==> Destroy AWS: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform aws
# shellcheck source=scripts/lib/aws-env.sh
source "$REPO_ROOT/scripts/lib/aws-env.sh"
k8s_plat_require_aws_credentials
k8s_plat_load_provider_vars

cd "$ENV_DIR"
# shellcheck disable=SC2086
terraform destroy -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

if [[ -f "$KUBECONFIG_FILE" ]]; then
  rm -f "$KUBECONFIG_FILE"
  echo "Removed $KUBECONFIG_FILE"
fi
if [[ -f "$INVENTORY_FILE" ]]; then
  rm -f "$INVENTORY_FILE"
  echo "Removed $INVENTORY_FILE"
fi

echo "AWS cluster destroyed."
