#!/usr/bin/env bash
# Phase 90 on the jump host. Env: OCP_INSTALL, OCP_CNI, OCP_CILIUM_VERSION, OCP_CILIUM_KPR

set -euo pipefail
export KUBECONFIG="${OCP_INSTALL}/auth/kubeconfig"

echo "==> network config"
oc get network.config cluster -o jsonpath='    networkType={.status.networkType} clusterNetwork={.status.clusterNetwork[*].cidr} serviceNetwork={.status.serviceNetwork[*]}{"\n"}'
oc get network.operator cluster -o jsonpath='    deployKubeProxy={.spec.deployKubeProxy}{"\n"}'
if [[ "${OCP_CNI}" == "Cilium" && "${OCP_CILIUM_KPR}" == "true" ]]; then
  if oc get pods -A --no-headers | awk '/kube-proxy/ {found = 1} END {exit !found}'; then
    echo "    WARNING: kube-proxy pods exist although kube_proxy_replacement is true"
  else
    echo "    no kube-proxy pods (Cilium serves Services)"
  fi
fi

if [[ "${OCP_CNI}" == "Cilium" ]]; then
  echo "==> cilium-dbg status --brief (every agent)"
  for pod in $(oc -n cilium get pods -l k8s-app=cilium -o name); do
    node="$(oc -n cilium get "${pod}" -o jsonpath='{.spec.nodeName}')"
    echo "    ${node}: $(oc -n cilium exec "${pod}" -c cilium-agent -- cilium-dbg status --brief 2>&1 | tr '\n' ' ')"
  done

  echo "==> connectivity check (cilium v${OCP_CILIUM_VERSION} examples)"
  oc create namespace cilium-test --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc label namespace cilium-test --overwrite \
    pod-security.kubernetes.io/enforce=privileged \
    security.openshift.io/scc.podSecurityLabelSync=false >/dev/null
  oc adm policy add-scc-to-group privileged system:serviceaccounts:cilium-test >/dev/null
  oc apply -n cilium-test -f "https://raw.githubusercontent.com/cilium/cilium/v${OCP_CILIUM_VERSION}/examples/kubernetes/connectivity-check/connectivity-check.yaml" >/dev/null
  if oc -n cilium-test wait deployment --all --for=condition=Available --timeout=600s >/dev/null; then
    echo "    all connectivity-check deployments Available"
  else
    echo "    some checks are not Available (multi-node checks need 2+ schedulable nodes):"
    oc -n cilium-test get pods --no-headers | awk '$2 !~ /^1\/1$/ {print "      " $0}'
    exit 1
  fi
  oc -n cilium-test get pods -o wide --no-headers | awk '{print "    " $1, $2, $3, $7}'
else
  echo "==> OVNKubernetes"
  oc -n openshift-ovn-kubernetes get daemonset ovnkube-node -o wide | sed 's/^/    /'
  oc -n openshift-ovn-kubernetes rollout status daemonset/ovnkube-node --timeout=300s | sed 's/^/    /'
fi
