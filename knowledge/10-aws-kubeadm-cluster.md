# AWS kubeadm cluster (2 nodes)

**Prerequisites:** [09-aws-terraform-learning-path.md](./09-aws-terraform-learning-path.md) lessons **AWS-0** through **AWS-7** (SSH to control plane works).

Use **`terraform output kubeadm_control_plane_endpoint`** for the API endpoint (EIP).

Pin one Kubernetes minor version on **both nodes** (example **1.31** — check [pkgs.k8s.io](https://pkgs.k8s.io) for current patch).

---

## Lesson K-1 — Prepare both nodes

Run on **control plane** and **worker** (SSH as `ubuntu`).

```bash
# swap off
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# modules + sysctl
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
sudo sysctl --system

# containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# kubeadm, kubelet, kubectl (adjust version)
K8S_VERSION=1.31
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

**Checkpoint:** `kubeadm version` on both nodes.

---

## Lesson K-2 — Init control plane

On **control plane only** (replace `<EIP>` from terraform output):

```bash
CP_ENDPOINT="<EIP>:6443"
sudo kubeadm init \
  --control-plane-endpoint="${CP_ENDPOINT}" \
  --pod-network-cidr=192.168.0.0/16 \
  --upload-certs

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
kubectl get nodes
```

Save the **`kubeadm join`** command from init output.

**Checkpoint:** Control plane node **Ready**.

---

## Lesson K-3 — Join worker

On **worker**:

```bash
# paste kubeadm join ... from K-2
sudo kubeadm join ...
```

On **control plane**:

```bash
kubectl get nodes
```

**Checkpoint:** Two nodes **Ready**.

---

## Lesson K-4 — kubeconfig on Mac

From repo root on your Mac:

```bash
scp -i infra/terraform/aws-kubeadm/environments/aws-dev/.ssh/aws-dev-key.pem \
  ubuntu@<EIP>:~/.kube/config .kube/aws-dev.yaml
```

Edit `.kube/aws-dev.yaml` if needed: `server: https://<EIP>:6443`

```bash
source scripts/kubeconfig-setup.sh .kube/aws-dev.yaml
kubectl get nodes -o wide
```

**Next:** [11-aws-platform-gitops.md](./11-aws-platform-gitops.md) — AWS CCM, Argo bootstrap, GitOps (not in repo yet for `aws-dev` profile).

---

## CKA drills (same cluster)

Practice in namespace `cka-practice`: taints, drains, NetworkPolicy, RBAC, PV/PVC. Avoid breaking `argocd`, `ingress-nginx`, `cert-manager` once installed.

---

## Reset before terraform destroy

On worker (from CP: `kubectl drain <worker> --ignore-daemonsets`):

```bash
sudo kubeadm reset -f
```

On control plane:

```bash
sudo kubeadm reset -f
```

Then [Lesson AWS-15](./09-aws-terraform-learning-path.md#lesson-aws-15-teardown).
