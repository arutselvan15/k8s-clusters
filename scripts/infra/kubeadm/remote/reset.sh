#!/usr/bin/env bash
# kubeadm reset on one node. Streamed over SSH stdin; not copied.

set -euo pipefail

if command -v kubeadm >/dev/null 2>&1; then
  sudo kubeadm reset -f
else
  echo "    kubeadm not installed; skip"
fi
sudo rm -rf /etc/cni/net.d "${HOME}/.kube"
