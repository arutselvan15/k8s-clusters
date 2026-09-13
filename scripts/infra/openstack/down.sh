#!/usr/bin/env bash
# Destroy OpenStack kubeadm lab VMs. Independent of Kind and AWS.
# Does not delete the existing tenant network (data source only).

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_DIR="${REPO_ROOT}/infra/terraform/environments/openstack"
AUTO_APPROVE=""
CLUSTER_SPEC=""
K8S_TF_VAR_ARGS=()

# shellcheck source=scripts/lib/os-env.sh
source "$REPO_ROOT/scripts/lib/os-env.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/openstack/down.sh [cluster] [-y]

Destroy the OpenStack lab for one cluster config.
Removes instances, ports, security group, keypair, and the Octavia ingress LB if enabled.
Does not delete the existing Neutron network (lookup only).
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

k8s_plat_resolve_cluster_config openstack "${CLUSTER_SPEC}"
k8s_plat_apply_cluster_outputs

if [[ ! -f "${K8S_PLAT_TFSTATE}" && ! -d "${ENV_DIR}/.terraform" ]]; then
  echo "No Terraform state for cluster ${K8S_PLAT_CLUSTER_NAME}; nothing to destroy."
  k8s_plat_purge_cluster_outputs
  exit 0
fi

echo "==> Destroy OpenStack cluster ${K8S_PLAT_CLUSTER_NAME}: ${ENV_DIR}"
"$REPO_ROOT/scripts/lib/require-tools.sh" terraform
k8s_plat_require_os_credentials
k8s_plat_load_os_provider_vars

cd "$ENV_DIR"
k8s_plat_terraform_init "$ENV_DIR"
# shellcheck disable=SC2086
terraform destroy -input=false $AUTO_APPROVE "${K8S_TF_VAR_ARGS[@]}"

k8s_plat_purge_cluster_outputs
echo "OpenStack cluster ${K8S_PLAT_CLUSTER_NAME} destroyed (existing network left in place)."
