#!/usr/bin/env bash
# Manifests: create install manifests and add a selected third-party CNI.
#
# Runs on: laptop (helm template) + jump host (openshift-install create manifests).
#
# Why: OVNKubernetes is built into OpenShift and needs no extra manifest. With
# networkType: Cilium the Cluster Network Operator deploys Multus but no pod
# network, so the Cilium manifests must be present before bootstrap.
#
# Adds to install/manifests/:
#   cilium-00-namespace.yml          ns 'cilium', run-level 0 (SCC admission
#                                    skips it; agents need hostNetwork/privileged)
#   cilium-<kind>-<name>.yml         upstream chart <cilium.version>, rendered
#                                    with OpenShift values (see below)
#   cluster-network-03-config.yml    operator Network: deployKubeProxy false
#                                    (only when kube_proxy_replacement: true)
#
# OpenShift-specific chart values:
#   cni.binPath /var/lib/cni/bin, cni.confPath /var/run/multus/cni/net.d,
#   cni.exclusive false     -> Multus stays the node's CNI entry point
#   ipam cluster-pool = clusterNetwork, mask = hostPrefix
#   tunnel vxlan port 4789  -> already open in the installer's security groups
#   clusterHealthPort 9940, hubble 9941 -> inside the open 9000-9999 range
#   k8sServiceHost api-int  -> agents reach the API before Services work
#
# Learn: ls install/manifests install/openshift on the jump host - this is
# everything the bootstrap node will apply.

ocp_load_outputs

if [[ "${OCP_CNI}" == "OVNKubernetes" ]]; then
  ocp_step "OVNKubernetes is selected; no third-party CNI manifests are needed"
  ocp_remote 50-manifests.sh
  ocp_ssh "grep -H networkType ${OCP_REMOTE_INSTALL}/manifests/cluster-network-02-config.yml | sed 's/^/    /'"
  exit 0
fi

"${REPO_ROOT}/scripts/lib/require-tools.sh" helm yq

render="${OCP_OUT_DIR}/manifests"
rm -rf "${render}"
mkdir -p "${render}/cilium"

ocp_step "Cilium ${OCP_CILIUM_VERSION} values (${render}/cilium-values.yaml)"
kpr_values="kubeProxyReplacement: false"
if [[ "${OCP_CILIUM_KPR}" == "true" ]]; then
  kpr_values="kubeProxyReplacement: true
k8sServiceHost: ${OCP_API_INT_HOST}
k8sServicePort: 6443"
fi
cat >"${render}/cilium-values.yaml" <<EOF
cluster:
  name: ${OCP_CLUSTER_NAME}
${kpr_values}
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
    - ${OCP_CLUSTER_NETWORK}
    clusterPoolIPv4MaskSize: ${OCP_HOST_PREFIX}
routingMode: tunnel
tunnelProtocol: vxlan
tunnelPort: 4789
clusterHealthPort: 9940
cni:
  binPath: /var/lib/cni/bin
  confPath: /var/run/multus/cni/net.d
  exclusive: false
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup
securityContext:
  privileged: true
operator:
  replicas: 2
prometheus:
  enabled: true
hubble:
  enabled: ${OCP_CILIUM_HUBBLE}
  listenAddress: ":9941"
  peerService:
    targetPort: 9941
  relay:
    enabled: ${OCP_CILIUM_HUBBLE}
  ui:
    enabled: ${OCP_CILIUM_HUBBLE}
  tls:
    auto:
      method: cronJob
EOF

ocp_step "helm template cilium ${OCP_CILIUM_VERSION} (kube ${OCP_KUBE_VERSION})"
helm template cilium cilium \
  --repo https://helm.cilium.io \
  --version "${OCP_CILIUM_VERSION}" \
  --namespace cilium \
  --kube-version "${OCP_KUBE_VERSION}" \
  -f "${render}/cilium-values.yaml" >"${render}/cilium-all.yaml"

cat >"${render}/cilium/cilium-00-namespace.yml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cilium
  labels:
    openshift.io/run-level: "0"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    security.openshift.io/scc.podSecurityLabelSync: "false"
EOF
# One object per file, named <kind>-<name>, like the Isovalent release manifests.
(cd "${render}/cilium" && yq -s '"cilium-" + (.kind | downcase) + "-" + .metadata.name' ../cilium-all.yaml)

if [[ "${OCP_CILIUM_KPR}" == "true" ]]; then
  cat >"${render}/cilium/cluster-network-03-config.yml" <<EOF
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  clusterNetwork:
  - cidr: ${OCP_CLUSTER_NETWORK}
    hostPrefix: ${OCP_HOST_PREFIX}
  serviceNetwork:
  - ${OCP_SERVICE_NETWORK}
  deployKubeProxy: false
EOF
fi
echo "    $(find "${render}/cilium" -type f | wc -l | tr -d ' ') files in ${render}/cilium"

ocp_step "openshift-install create manifests (jump host)"
ocp_remote 50-manifests.sh

ocp_step "copy Cilium manifests into ${OCP_REMOTE_INSTALL}/manifests/"
# COPYFILE_DISABLE: macOS tar would otherwise add ._* files that the
# installer tries to parse as manifests.
COPYFILE_DISABLE=1 tar -C "${render}/cilium" -cf - . | ocp_ssh "tar -C ${OCP_REMOTE_INSTALL}/manifests -xf -"

ocp_step "what the bootstrap node will apply"
ocp_ssh "cd ${OCP_REMOTE_INSTALL} && grep -H networkType manifests/cluster-network-02-config.yml && ls manifests | grep -c '^cilium-' | sed 's/^/    cilium manifests: /' && ls manifests/cluster-network-03-config.yml 2>/dev/null | sed 's/^/    /' || true"
