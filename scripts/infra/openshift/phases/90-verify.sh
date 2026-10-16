#!/usr/bin/env bash
# Verify: selected CNI health, connectivity checks, and laptop access.
#
# Runs on: jump host (checks) + laptop (copies kubeconfig and password).
#
# Why: "install complete" means OpenShift's operators are happy. It does not
# prove pod-to-pod across nodes, Services without kube-proxy, or
# NetworkPolicy. Cilium's connectivity-check deployments exercise each of
# those; OVNKubernetes uses OpenShift's standard operator and node checks.
#
# Does:
#   - selected CNI agent health; Cilium additionally checks kube-proxy absence
#   - Cilium only: cilium-test namespace and connectivity-check.yaml
#   - copies install/auth/{kubeconfig,kubeadmin-password} to
#     sensitive/openshift/<cluster>/
#   - prints the /etc/hosts lines your laptop needs (no DNS zone exists)
#
# Learn: oc get network.config cluster -o yaml
#        (and cilium-dbg service list when Cilium is selected)

ocp_load_outputs
ocp_remote 90-verify.sh \
  "OCP_CNI=${OCP_CNI}" \
  "OCP_CILIUM_VERSION=${OCP_CILIUM_VERSION}" \
  "OCP_CILIUM_KPR=${OCP_CILIUM_KPR}"

ocp_step "kubeconfig + kubeadmin password -> ${OCP_OUT_DIR}/"
ocp_get "${OCP_REMOTE_INSTALL}/auth/kubeconfig" "${OCP_OUT_DIR}/kubeconfig"
ocp_get "${OCP_REMOTE_INSTALL}/auth/kubeadmin-password" "${OCP_OUT_DIR}/kubeadmin-password"

# With network_mode=existing there are no floating IPs: the VIPs themselves
# are what the laptop talks to, from anywhere that routes to the machine
# network.
laptop_api_ip="${OCP_API_FIP:-${OCP_API_VIP}}"
laptop_ingress_ip="${OCP_INGRESS_FIP:-${OCP_INGRESS_VIP}}"

cat <<EOF

Laptop access (sudo vi /etc/hosts; there is no DNS zone for ${OCP_BASE_DOMAIN}):
  ${laptop_api_ip} ${OCP_API_HOST}
  ${laptop_ingress_ip} console-openshift-console.${OCP_APPS_DOMAIN} oauth-openshift.${OCP_APPS_DOMAIN} downloads-openshift-console.${OCP_APPS_DOMAIN}

Then:
  source scripts/lib/kubeconfig-setup.sh ${OCP_OUT_DIR}/kubeconfig
  oc get nodes
  open https://console-openshift-console.${OCP_APPS_DOMAIN}   # kubeadmin / ${OCP_OUT_DIR}/kubeadmin-password

EOF
if [[ "${OCP_CNI}" == "Cilium" && "${OCP_CILIUM_HUBBLE}" == "true" ]]; then
  echo "Hubble UI:  oc -n cilium port-forward svc/hubble-ui 12000:80  ->  http://localhost:12000"
fi
if [[ "${OCP_CNI}" == "Cilium" ]]; then
  echo "Clean up the test pods: oc delete namespace cilium-test"
fi
