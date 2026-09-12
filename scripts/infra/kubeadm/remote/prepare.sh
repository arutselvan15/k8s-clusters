#!/usr/bin/env bash
# 8a — prepare a node (control plane or worker). Streamed over SSH stdin; not copied.
# Env: K8S_VERSION (minor, e.g. 1.32)

set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.32}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

if command -v cloud-init >/dev/null 2>&1; then
  sudo cloud-init status --wait || true
fi

sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
# Apply only this file. `sysctl --system` also reloads AMI defaults; on EC2 those
# often print Invalid argument for accept_source_route / promote_secondaries.
sudo sysctl -p /etc/sysctl.d/k8s.conf >/dev/null

wait_apt() {
  local n=0
  while [[ "${n}" -lt 60 ]]; do
    if sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
      return 0
    fi
    n=$((n + 1))
    sleep 5
  done
  echo "apt-get update failed (dpkg lock or network)" >&2
  return 1
}

wait_apt
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

sudo mkdir -p /etc/apt/keyrings
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
wait_apt
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
kubeadm version
