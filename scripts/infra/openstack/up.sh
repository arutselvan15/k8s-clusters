#!/usr/bin/env bash
# Day 0 — kubeadm on OpenStack VMs. Independent of Kind and AWS.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_DIR="${REPO_ROOT}/infra/terraform/environments/openstack"
AUTO_APPROVE=""
K8S_TF_VAR_ARGS=()

usage() {
  cat <<EOF
Usage: ./scripts/infra/openstack/up.sh [-y]

Apply OpenStack lab (terraform environments/openstack).
Needs k8s-platform/.openstack/clouds.yaml and .openstack/config.

Attaches VMs to an existing Neutron network (does not create or delete that network).

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

echo "==> OpenStack: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform
# shellcheck source=scripts/lib/os-env.sh
source "$REPO_ROOT/scripts/lib/os-env.sh"
k8s_plat_require_os_credentials
k8s_plat_load_os_provider_vars

if command -v openstack >/dev/null 2>&1; then
  echo "==> OpenStack identity (OS_CLOUD=${OS_CLOUD}; token secret not printed)"
  openstack token issue -f value -c project_id -c user_id -c expires || true
else
  echo "==> openstack CLI not on PATH (optional). Terraform uses clouds.yaml."
fi

cd "$ENV_DIR"
terraform init -input=false
# shellcheck disable=SC2086
terraform apply -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

write_kubeadm_inventory() {
  local inv="${REPO_ROOT}/.kube/os-inventory.env"
  local cp_host ssh_key workers k8s_version ssh_user
  cp_host="$(terraform output -raw control_plane_public_ip)"
  ssh_key="$(terraform output -raw ssh_private_key_path)"
  workers="$(terraform output -raw worker_public_ips)"
  ssh_user="$(terraform output -raw ssh_user)"
  k8s_version="$(k8s_plat_os_config_get kubernetes_version 2>/dev/null || echo "1.32")"
  mkdir -p "${REPO_ROOT}/.kube"
  cat >"${inv}" <<EOF
SSH_USER=${ssh_user}
SSH_KEY=${ssh_key}
CONTROL_PLANE_HOST=${cp_host}
CONTROL_PLANE_ENDPOINT=${cp_host}
WORKER_HOSTS=${workers}
K8S_VERSION=${k8s_version}
POD_CIDR=192.168.0.0/16
KUBECONFIG_FILE=${REPO_ROOT}/.kube/os-dev.yaml
EOF
  chmod 600 "${inv}"
  echo "==> Wrote kubeadm inventory ${inv}"
}

write_kubeadm_inventory

echo ""
echo "Terraform openstack applied (VMs only; Kubernetes is separate)."
echo "Existing Neutron network was looked up, not created."
terraform output
echo ""
echo "Next (kubeadm, uses .kube/os-inventory.env):"
echo "  ${REPO_ROOT}/scripts/infra/kubeadm/up.sh -i .kube/os-inventory.env"
echo "Then Day 1: source scripts/lib/kubeconfig-setup.sh .kube/os-dev.yaml"
echo "  ${REPO_ROOT}/bootstrap/bootstrap.sh dev"
