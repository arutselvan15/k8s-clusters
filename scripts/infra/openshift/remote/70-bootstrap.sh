#!/usr/bin/env bash
# Phase 70 on the jump host. Env: OCP_WORK, OCP_INSTALL, OCP_CLUSTER_NAME, OCP_CLOUD, OCP_CNI

set -euo pipefail
export OS_CLOUD="${OCP_CLOUD}"

if [[ ! -f "${OCP_INSTALL}/metadata.json" ]]; then
  echo "No cluster in ${OCP_INSTALL} yet - run phase 60 first." >&2
  exit 1
fi
if [[ -f "${OCP_WORK}/create.rc" && "$(cat "${OCP_WORK}/create.rc")" != "0" ]]; then
  echo "openshift-install create cluster failed (rc $(cat "${OCP_WORK}/create.rc")):" >&2
  tail -n 30 "${OCP_WORK}/create.log" >&2
  exit 1
fi

export KUBECONFIG="${OCP_INSTALL}/auth/kubeconfig"
echo "==> VMs so far"
openstack server list -f value -c Name -c Status -c Networks --name "^${OCP_CLUSTER_NAME}-" | sed 's/^/    /' || true

echo "==> openshift-install wait-for bootstrap-complete"
openshift-install wait-for bootstrap-complete --dir "${OCP_INSTALL}" --log-level info 2>&1 | sed 's/^/    /'

echo "==> nodes"
oc get nodes -o wide | sed 's/^/    /'
if [[ "${OCP_CNI}" == "Cilium" ]]; then
  echo "==> Cilium"
  oc -n cilium get pods -o wide | sed 's/^/    /'
  oc -n cilium exec ds/cilium -c cilium-agent -- cilium-dbg status --brief 2>&1 | sed 's/^/    /' || true
else
  echo "==> OVNKubernetes"
  oc -n openshift-ovn-kubernetes get pods -o wide | sed 's/^/    /'
fi
