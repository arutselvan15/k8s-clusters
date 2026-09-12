#!/usr/bin/env bash
# Day 0 — kubeadm on EC2. Independent of Kind.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_DIR="${REPO_ROOT}/infra/terraform/environments/ec2"
AUTO_APPROVE=""
K8S_TF_VAR_ARGS=()

usage() {
  cat <<EOF
Usage: ./scripts/infra/aws/up.sh [-y]

Apply AWS EC2 lab (terraform environments/ec2).
Needs k8s-platform/.aws/credentials and .aws/config.

  -y, --yes   terraform apply -auto-approve

Teardown: $(dirname "$0")/down.sh
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

echo "==> AWS: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform aws
# shellcheck source=scripts/lib/aws-env.sh
source "$REPO_ROOT/scripts/lib/aws-env.sh"
k8s_plat_require_aws_credentials
k8s_plat_load_provider_vars
echo "==> AWS identity (project credentials: ${AWS_SHARED_CREDENTIALS_FILE})"
aws sts get-caller-identity --no-cli-pager

cd "$ENV_DIR"
terraform init -input=false
# shellcheck disable=SC2086
terraform apply -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

write_kubeadm_inventory() {
  local inv="${REPO_ROOT}/.kube/aws-inventory.env"
  local cp_host ssh_key workers k8s_version
  cp_host="$(terraform output -raw control_plane_public_ip)"
  ssh_key="$(terraform output -raw ssh_private_key_path)"
  workers="$(terraform output -raw worker_public_ips)"
  k8s_version="$(k8s_plat_aws_config_get kubernetes_version 2>/dev/null || echo "1.32")"
  mkdir -p "${REPO_ROOT}/.kube"
  cat >"${inv}" <<EOF
SSH_USER=ubuntu
SSH_KEY=${ssh_key}
CONTROL_PLANE_HOST=${cp_host}
CONTROL_PLANE_ENDPOINT=${cp_host}
WORKER_HOSTS=${workers}
K8S_VERSION=${k8s_version}
POD_CIDR=192.168.0.0/16
KUBECONFIG_FILE=${REPO_ROOT}/.kube/aws-dev.yaml
EOF
  chmod 600 "${inv}"
  echo "==> Wrote kubeadm inventory ${inv}"
}

write_kubeadm_inventory

echo ""
echo "Terraform aws applied (VMs only; Kubernetes is separate)."
terraform output
echo ""
echo "Next (kubeadm, uses .kube/aws-inventory.env):"
echo "  ${REPO_ROOT}/scripts/infra/kubeadm/up.sh"
echo "Then Day 1: source scripts/lib/kubeconfig-setup.sh .kube/aws-dev.yaml"
echo "  ${REPO_ROOT}/bootstrap/bootstrap.sh dev"
