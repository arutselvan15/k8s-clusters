#!/usr/bin/env bash
# 8b — kubeadm init + Calico on the control plane. Streamed over SSH stdin; not copied.
# Env: CP_PUBLIC, POD_CIDR, CALICO_MANIFEST

set -euo pipefail

: "${CP_PUBLIC:?CP_PUBLIC is the control-plane public IP}"
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
CALICO_MANIFEST="${CALICO_MANIFEST:-https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml}"

mkdir -p "${HOME}/.kube"

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "    already initialized; skipping kubeadm init"
else
  sudo kubeadm init \
    --control-plane-endpoint="${CP_PUBLIC}:6443" \
    --apiserver-cert-extra-sans="${CP_PUBLIC}" \
    --pod-network-cidr="${POD_CIDR}"
fi

sudo cp /etc/kubernetes/admin.conf "${HOME}/.kube/config"
sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"
kubectl apply -f "${CALICO_MANIFEST}"
kubectl get nodes
