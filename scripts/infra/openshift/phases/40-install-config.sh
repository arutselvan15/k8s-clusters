#!/usr/bin/env bash
# install-config: render install-config.yaml from the cluster config.
#
# Runs on: laptop (render) -> jump host (copy into the install dir).
#
# Why: install-config.yaml is the only input the installer really has. The
# interactive `openshift-install create install-config` wizard cannot set
# networkType or the bring-your-own subnet, so it is written directly.
#
# Key fields:
#   networking.networkType: config   OVNKubernetes is built in; Cilium is
#                                    added as extra manifests in phase 50
#   networking.machineNetwork        must equal the subnet CIDR from phase 10
#   platform.openstack.controlPlanePort   reuse that subnet, not a new net
#   apiVIPs / ingressVIPs            keepalived addresses inside that subnet
#   apiFloatingIP / ingressFloatingIP     FIPs from phase 10, attached by the
#                                    installer to the VIP ports it creates.
#                                    Omitted, with externalNetwork, when
#                                    terraform.network.mode is existing: there
#                                    the VIPs already route.
#   defaultMachinePlatform.rootVolume     boot nodes from Cinder (flavor disk
#                                    is only 50 GB). Omitted when
#                                    openshift.root_volume_gb is 0, which
#                                    boots them from that local disk instead.
#
# The installer CONSUMES install-config.yaml (deletes it) in phase 50, so a
# copy is kept as install-config.yaml.bak on the jump host and locally in
# sensitive/openshift/<cluster>/install-config.yaml (has the pull secret).
#
# Learn: openshift-install explain installconfig.platform.openstack

"${REPO_ROOT}/scripts/lib/require-tools.sh" jq
ocp_load_outputs

if ocp_ssh "test -f ${OCP_REMOTE_INSTALL}/metadata.json"; then
  ocp_die "A cluster was already created from ${OCP_REMOTE_INSTALL}. Destroy it first (down.sh ${OCP_CLUSTER_ID} cluster)."
fi

local_ic="${OCP_OUT_DIR}/install-config.yaml"
pull_secret="$(jq -c . "${OCP_PULL_SECRET}")"

optional_os_image=""
if [[ -n "${OCP_CLUSTER_OS_IMAGE}" ]]; then
  optional_os_image="    clusterOSImage: ${OCP_CLUSTER_OS_IMAGE}"
fi

optional_proxy=""
if [[ -n "${OCP_HTTP_PROXY}${OCP_HTTPS_PROXY}" ]]; then
  optional_proxy="proxy:
  httpProxy: ${OCP_HTTP_PROXY}
  httpsProxy: ${OCP_HTTPS_PROXY}
  noProxy: ${OCP_NO_PROXY:-${OCP_MACHINE_CIDR},${OCP_CLUSTER_NETWORK},${OCP_SERVICE_NETWORK},.${OCP_CLUSTER_NAME}.${OCP_BASE_DOMAIN}}"
fi

# network_mode=existing has no floating IPs, and externalNetwork exists only
# to allocate them, so both are left out and the VIPs are reached directly.
optional_external=""
if [[ -n "${OCP_EXTERNAL_NETWORK}" ]]; then
  optional_external="    externalNetwork: ${OCP_EXTERNAL_NETWORK}"
fi
optional_fips=""
if [[ -n "${OCP_API_FIP}" && -n "${OCP_INGRESS_FIP}" ]]; then
  optional_fips="    apiFloatingIP: ${OCP_API_FIP}
    ingressFloatingIP: ${OCP_INGRESS_FIP}"
fi

# root_volume_gb 0: no rootVolume, so nodes boot from the flavor's local disk
# and the cluster needs no Cinder quota for them.
optional_root_volume=""
if (( OCP_ROOT_VOLUME_GB > 0 )); then
  optional_root_volume="    defaultMachinePlatform:
      rootVolume:
        size: ${OCP_ROOT_VOLUME_GB}
        types:
        - ${OCP_VOLUME_TYPE}"
fi

ocp_step "rendering ${local_ic}"
(
  umask 077
  cat >"${local_ic}" <<EOF
apiVersion: v1
baseDomain: ${OCP_BASE_DOMAIN}
metadata:
  name: ${OCP_CLUSTER_NAME}
controlPlane:
  name: master
  architecture: amd64
  hyperthreading: Enabled
  replicas: ${OCP_CP_REPLICAS}
  platform:
    openstack:
      type: ${OCP_CP_FLAVOR}
compute:
- name: worker
  architecture: amd64
  hyperthreading: Enabled
  replicas: ${OCP_COMPUTE_REPLICAS}
  platform:
    openstack:
      type: ${OCP_COMPUTE_FLAVOR}
networking:
  networkType: ${OCP_CNI}
  machineNetwork:
  - cidr: ${OCP_MACHINE_CIDR}
  clusterNetwork:
  - cidr: ${OCP_CLUSTER_NETWORK}
    hostPrefix: ${OCP_HOST_PREFIX}
  serviceNetwork:
  - ${OCP_SERVICE_NETWORK}
platform:
  openstack:
    cloud: ${OCP_CLOUD}
${optional_external}
${optional_fips}
    apiVIPs:
    - ${OCP_API_VIP}
    ingressVIPs:
    - ${OCP_INGRESS_VIP}
    controlPlanePort:
      network:
        name: ${OCP_NETWORK_NAME}
      fixedIPs:
      - subnet:
          name: ${OCP_SUBNET_NAME}
${optional_root_volume}
${optional_os_image}
${optional_proxy}
publish: External
pullSecret: '${pull_secret}'
sshKey: '${OCP_SSH_PUBLIC_KEY}'
EOF
)

ocp_step "copy to jump host ${OCP_REMOTE_INSTALL}/ (fresh install dir)"
ocp_ssh "rm -rf ${OCP_REMOTE_INSTALL} && mkdir -p ${OCP_REMOTE_INSTALL}"
ocp_put "${local_ic}" "${OCP_REMOTE_INSTALL}/install-config.yaml"
ocp_put "${local_ic}" "${OCP_REMOTE_WORK}/install-config.yaml.bak"

echo ""
echo "install-config.yaml (pullSecret redacted):"
sed -e "s|^pullSecret: .*|pullSecret: '<redacted>'|" -e '/^$/d' "${local_ic}" | sed 's/^/    /'
