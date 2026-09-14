#!/usr/bin/env bash
# Install the OpenStack Cloud Controller Manager so type: LoadBalancer Services
# create Octavia LBs. Run after kubeadm/up.sh on a cluster whose config.yaml has
# kubeadm.cloud_provider: external. See docs/infra/openstack.md.

if [ -z "${BASH_VERSION:-}" ] || [ -n "${POSIXLY_CORRECT:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLUSTER_SPEC=""
# Chart major.minor tracks the Kubernetes minor version.
CHART_VERSION="${OCCM_CHART_VERSION:-2.32.0}"
CHART_REPO="https://kubernetes.github.io/cloud-provider-openstack"

usage() {
  cat <<EOF
Usage: ./scripts/infra/openstack/occm.sh <cluster>

Writes sensitive/openstack/<name>/cloud.conf from clouds.yaml, creates the
cloud-config Secret, and installs openstack-cloud-controller-manager.

  cluster   id or path. clusters/openstack/<id>/config.yaml

Env:
  OCCM_CHART_VERSION   chart version (default ${CHART_VERSION}; 2.x tracks k8s 1.x)

Safe to re-run: the Secret and the Helm release are both upserted.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -c | --cluster) CLUSTER_SPEC="${2:?cluster config required}"; shift ;;
    *) CLUSTER_SPEC="$1" ;;
  esac
  shift
done

"$REPO_ROOT/scripts/lib/require-tools.sh" helm kubectl openstack yq
# shellcheck source=scripts/lib/os-env.sh
source "$REPO_ROOT/scripts/lib/os-env.sh"
k8s_plat_resolve_cluster_config openstack "${CLUSTER_SPEC}"
k8s_plat_apply_cluster_outputs
k8s_plat_require_os_credentials

CLOUD_PROVIDER="$(k8s_plat_yaml_get "${K8S_PLAT_CLUSTER_CONFIG}" cloud_provider || true)"
if [[ "${CLOUD_PROVIDER}" != "external" ]]; then
  echo "kubeadm.cloud_provider is '${CLOUD_PROVIDER:-unset}' in ${K8S_PLAT_CLUSTER_CONFIG}." >&2
  echo "Set it to 'external' and re-bootstrap before installing OCCM (docs/infra/openstack.md)." >&2
  exit 1
fi

SUBNET_NAME="$(k8s_plat_yaml_require "${K8S_PLAT_CLUSTER_CONFIG}" subnet_name)" || exit 1
KUBECONFIG_FILE="${K8S_PLAT_CLUSTER_KUBECONFIG}"
if [[ ! -f "${KUBECONFIG_FILE}" ]]; then
  echo "Kubeconfig not found: ${KUBECONFIG_FILE}" >&2
  echo "Run ./scripts/infra/kubeadm/up.sh openstack ${K8S_PLAT_CLUSTER_CONFIG_ID} first." >&2
  exit 1
fi
export KUBECONFIG="${KUBECONFIG_FILE}"

echo "==> OCCM for ${K8S_PLAT_CLUSTER_NAME} (chart ${CHART_VERSION})"

echo "==> Resolving ${SUBNET_NAME}"
SUBNET_ID="$(openstack subnet show "${SUBNET_NAME}" -f value -c id)"
if [[ -z "${SUBNET_ID}" ]]; then
  echo "Could not resolve subnet ${SUBNET_NAME}" >&2
  exit 1
fi
echo "    subnet-id ${SUBNET_ID}"

# cloud.conf holds the application credential, so it stays in gitignored
# sensitive/ and is fed to the Secret by file. It is never put in Helm values.
CLOUD_CONF="${K8S_PLAT_CLUSTER_DIR}/cloud.conf"
mkdir -p "${K8S_PLAT_CLUSTER_DIR}"
(
  umask 077
  {
    echo "[Global]"
    echo "auth-url=$(yq -r '.clouds.openstack.auth.auth_url' "${OS_CLIENT_CONFIG_FILE}")"
    echo "application-credential-id=$(yq -r '.clouds.openstack.auth.application_credential_id' "${OS_CLIENT_CONFIG_FILE}")"
    echo "application-credential-secret=$(yq -r '.clouds.openstack.auth.application_credential_secret' "${OS_CLIENT_CONFIG_FILE}")"
    echo "region=$(yq -r '.clouds.openstack.region_name' "${OS_CLIENT_CONFIG_FILE}")"
    echo ""
    echo "[LoadBalancer]"
    # internal-lb skips the floating IP. The VIP is already a routable address
    # on this subnet, and the project floatingip quota is 0 — without this OCCM
    # auto-discovers an external network and fails with OverQuota.
    echo "internal-lb=true"
    echo "subnet-id=${SUBNET_ID}"
    echo "create-monitor=true"
    # NodePorts are allocated per Service, so the Terraform security group cannot
    # know them. OCCM opens exactly the ports it uses on the node Neutron ports.
    echo "manage-security-groups=true"
  } >"${CLOUD_CONF}"
)
if grep -qE '=(null)?$' "${CLOUD_CONF}"; then
  echo "cloud.conf has empty values; check auth keys in ${OS_CLIENT_CONFIG_FILE}" >&2
  exit 1
fi
echo "==> Wrote ${CLOUD_CONF} (gitignored, not printed)"

kubectl -n kube-system create secret generic cloud-config \
  --from-file=cloud.conf="${CLOUD_CONF}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add cpo "${CHART_REPO}" >/dev/null 2>&1 || true
helm repo update cpo >/dev/null
helm upgrade --install openstack-ccm cpo/openstack-cloud-controller-manager \
  --version "${CHART_VERSION}" \
  --namespace kube-system \
  --set secret.create=false \
  --set secret.name=cloud-config \
  --wait --timeout 5m

# cloud.conf is read at startup, so a re-run with changed settings needs a
# restart to take effect.
kubectl -n kube-system rollout restart daemonset/openstack-cloud-controller-manager
kubectl -n kube-system rollout status daemonset/openstack-cloud-controller-manager --timeout=3m

echo "==> Nodes (providerID should be openstack://..., uninitialized taint gone)"
kubectl get nodes -o custom-columns='NODE:.metadata.name,PROVIDER:.spec.providerID,TAINTS:.spec.taints[*].key'

echo ""
echo "OCCM installed. A type: LoadBalancer Service now creates an Octavia LB."
echo "  cd ../k8s-apps && ./scripts/apps.sh install ingress-nginx --cluster ${K8S_PLAT_CLUSTER_NAME}"
echo "  kubectl -n ingress-nginx get svc -w"
