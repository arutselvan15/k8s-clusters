#!/usr/bin/env bash
# Tear down an OpenShift lab in the reverse order it was built:
#   cluster  openshift-install destroy cluster (from the jump host)
#   infra    terraform destroy (jump host, and the network, router and FIPs
#            when terraform.network.mode is create)
# The installer must go first: its VMs and ports sit on the Terraform network,
# and only the jump host has the install dir (metadata.json) that names them.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/infra/openshift/lib.sh
source "${REPO_ROOT}/scripts/infra/openshift/lib.sh"

usage() {
  cat <<EOF
Usage: ./scripts/infra/openshift/down.sh [cluster] [cluster|infra|all] [-y] [--force]

  cluster   openshift-install destroy cluster on the jump host (~10 min)
  infra     terraform destroy; refuses while a cluster still exists
  all       both, in that order (default)

  -y, --yes   no confirmation prompts
  --force     infra even if the cluster was not destroyed (orphans its VMs)
EOF
}

CLUSTER=""
WHAT="all"
YES="false"
FORCE="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -y | --yes) YES="true" ;;
    --force) FORCE="true" ;;
    cluster | infra | all) WHAT="$1" ;;
    *) CLUSTER="$1" ;;
  esac
  shift
done

ocp_load_config "${CLUSTER}"

confirm() {
  [[ "${YES}" == "true" ]] && return 0
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

destroy_cluster() {
  if [[ ! -f "${OCP_ENV_FILE}" ]]; then
    echo "==> no jump host outputs; nothing for openshift-install to destroy"
    return 0
  fi
  ocp_load_outputs
  if ! ocp_ssh "test -f ${OCP_REMOTE_INSTALL}/metadata.json" 2>/dev/null; then
    echo "==> no cluster recorded in ${OCP_REMOTE_INSTALL}"
    return 0
  fi
  confirm "Destroy OpenShift cluster ${OCP_CLUSTER_NAME} (all its VMs, ports, volumes)?" || return 1
  ocp_step "openshift-install destroy cluster"
  ocp_ssh "set -e
    pidf=${OCP_REMOTE_WORK}/create.pid
    if [ -f \"\$pidf\" ] && kill -0 \"\$(cat \"\$pidf\")\" 2>/dev/null; then
      echo '    stopping running create cluster'; kill \"\$(cat \"\$pidf\")\"; sleep 5
    fi
    openshift-install destroy cluster --dir ${OCP_REMOTE_INSTALL} --log-level info 2>&1 | sed 's/^/    /'
    rm -rf ${OCP_REMOTE_INSTALL} ${OCP_REMOTE_WORK}/create.*"
  for p in 60-create 70-bootstrap 80-install 90-verify 50-manifests 40-install-config; do
    ocp_phase_clear "${p}"
  done
}

destroy_infra() {
  if [[ "${FORCE}" != "true" ]] && ocp_phase_done 60-create; then
    ocp_die "Phase 60 ran and the cluster is not destroyed. Run: down.sh ${OCP_CLUSTER_ID} cluster (or --force)."
  fi
  if [[ ! -f "${OCP_TFSTATE}" ]]; then
    echo "==> no Terraform state; nothing to destroy"
  else
    if [[ "${OCP_NETWORK_MODE}" == "existing" ]]; then
      confirm "Destroy the jump host for ${OCP_CLUSTER_NAME}? (${OCP_EXISTING_NETWORK} is not touched)" || return 1
    else
      confirm "Destroy jump host, network, router and floating IPs for ${OCP_CLUSTER_NAME}?" || return 1
    fi
    "${REPO_ROOT}/scripts/lib/require-tools.sh" terraform
    k8s_plat_require_os_credentials
    ocp_tf_vars
    cd "${OCP_TF_DIR}"
    k8s_plat_terraform_init "${OCP_TF_DIR}"
    terraform destroy -input=false -auto-approve "${OCP_TF_VARS[@]}"
  fi
  ocp_step "removing ${OCP_OUT_DIR}"
  rm -rf "${OCP_OUT_DIR}"
}

case "${WHAT}" in
  cluster) destroy_cluster ;;
  infra) destroy_infra ;;
  all)
    destroy_cluster
    destroy_infra
    ;;
esac
k8s_plat_s3_offer
