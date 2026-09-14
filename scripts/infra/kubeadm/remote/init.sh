#!/usr/bin/env bash
# 8b — kubeadm init on the control plane. Streamed over SSH stdin; not copied.
# Env: CP_PUBLIC, POD_CIDR, CNI
#
# The pod network is installed later, from the laptop (kubeadm/lib.sh), so this
# only has to get the API server up.

set -euo pipefail

: "${CP_PUBLIC:?CP_PUBLIC is the control-plane public IP}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
CNI="${CNI:-calico}"

mkdir -p "${HOME}/.kube"

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "    already initialized; skipping kubeadm init"
else
  init_args=(
    --control-plane-endpoint="${CP_PUBLIC}:6443"
    --apiserver-cert-extra-sans="${CP_PUBLIC}"
    --pod-network-cidr="${POD_CIDR}"
  )
  # Cilium serves Services from eBPF, so kube-proxy must never be installed —
  # the two would program the same traffic twice. Like cloud_provider this is
  # fixed at init: changing cni on a live cluster needs kubeadm/reset.sh first.
  if [[ "${CNI}" == "cilium" ]]; then
    init_args+=(--skip-phases=addon/kube-proxy)
    echo "    kube-proxy addon skipped (cilium kubeProxyReplacement)"
  fi
  sudo kubeadm init "${init_args[@]}"
fi

sudo cp /etc/kubernetes/admin.conf "${HOME}/.kube/config"
sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"
kubectl get nodes
