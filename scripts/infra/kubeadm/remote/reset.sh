#!/usr/bin/env bash
# kubeadm reset on one node. Streamed over SSH stdin; not copied.

set -euo pipefail

if command -v kubeadm >/dev/null 2>&1; then
  sudo kubeadm reset -f
else
  echo "    kubeadm not installed; skip"
fi
sudo rm -rf /etc/cni/net.d /var/lib/cni /var/run/cilium "${HOME}/.kube"

# kubeadm reset drops the config but not the CNI's own datapath links, so a
# cluster rebuilt with a different cni would inherit the old ones.
for link in cilium_host cilium_net cilium_vxlan vxlan.calico; do
  sudo ip link delete "${link}" 2>/dev/null || true
done
