#!/usr/bin/env bash
# Phase 80 on the jump host. Env: OCP_WORK, OCP_INSTALL

set -euo pipefail

if [[ ! -f "${OCP_INSTALL}/auth/kubeconfig" ]]; then
  echo "No ${OCP_INSTALL}/auth/kubeconfig - run phases 60 and 70 first." >&2
  exit 1
fi
export KUBECONFIG="${OCP_INSTALL}/auth/kubeconfig"

echo "==> openshift-install wait-for install-complete"
openshift-install wait-for install-complete --dir "${OCP_INSTALL}" --log-level info 2>&1 |
  sed -E 's/(password: ).*/\1<see install\/auth\/kubeadmin-password>/' | sed 's/^/    /'

echo "==> background create cluster"
for _ in $(seq 1 60); do
  [[ -f "${OCP_WORK}/create.rc" ]] && break
  sleep 10
done
echo "    create.rc=$(cat "${OCP_WORK}/create.rc" 2>/dev/null || echo 'still running')"

echo "==> cluster version / nodes / operators not yet Available"
oc get clusterversion | sed 's/^/    /'
oc get nodes | sed 's/^/    /'
oc get co --no-headers | awk '$3 != "True" || $5 == "True" {print "    " $0; n++} END {if (!n) print "    all ClusterOperators Available"}'
