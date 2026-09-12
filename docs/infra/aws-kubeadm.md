# Day 0 — AWS kubeadm

**Prerequisites:** [aws.md](./aws.md) lessons **AWS-0** through **AWS-7** (SSH to control plane works). Inventory exists at `sensitive/<env>/<cluster_name>/cluster.env` after `./scripts/infra/up.sh aws k8s-aws`.

## Automated (same as the remote scripts)

```bash
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

kubeadm is **not** Terraform. It SSHs using the inventory and streams [`scripts/infra/kubeadm/remote/`](../../scripts/infra/kubeadm/remote/) over stdin (no scp). Safe to re-run.

Pod CIDR is `192.168.0.0/16` so it does **not** overlap the VPC `10.0.0.0/16`.

Manual steps below are the CKA-style walkthrough (same commands as the remote scripts).

Pin one Kubernetes minor version on **every** node (`kubernetes_version` in `clusters/aws/k8s-aws/config.yaml`, default **1.32** — check [pkgs.k8s.io](https://pkgs.k8s.io) for current patch).

Use **`terraform output control_plane_public_ip`** for the API endpoint.

---

## Lesson K-1 — Prepare both nodes

Run on **control plane** and **worker** (SSH as `ubuntu`). Full script: [`scripts/infra/kubeadm/remote/prepare.sh`](../../scripts/infra/kubeadm/remote/prepare.sh).

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
sudo sysctl -p /etc/sysctl.d/k8s.conf

# containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# kubeadm, kubelet, kubectl (adjust version)
K8S_VERSION=1.32
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

On **control plane only** (replace `<PUBLIC_IP>` from terraform output):

```bash
CP_PUBLIC="<PUBLIC_IP>"
sudo kubeadm init \
  --control-plane-endpoint="${CP_PUBLIC}:6443" \
  --apiserver-cert-extra-sans="${CP_PUBLIC}" \
  --pod-network-cidr=192.168.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml
kubectl get nodes
```

Save the **`kubeadm join`** command from init output. Do not paste the token into chat or git.

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
ssh -i sensitive/aws/k8s-aws/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/ec2 output -raw control_plane_public_ip) \
  'sudo cat /etc/kubernetes/admin.conf' > sensitive/aws/k8s-aws/kubeconfig
chmod 600 sensitive/aws/k8s-aws/kubeconfig
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

`admin.conf` already has `https://<public-ip>:6443` because of `--control-plane-endpoint`.

**Next:** same [bootstrap](../bootstrap/) and [gitops](../gitops/) as any other environment. Cloud `LoadBalancer` ingress needs a cloud controller (AWS CCM is not in the repo yet); that is an infra/values difference, not a second GitOps tree.

---

## CKA drills (same cluster)

Practice in namespace `cka-practice`: taints, drains, NetworkPolicy, RBAC, PV/PVC. Avoid breaking `argocd`, `ingress-nginx`, `cert-manager` once installed.

---

## Reset before terraform destroy

```bash
./scripts/infra/kubeadm/reset.sh aws k8s-aws
./scripts/infra/down.sh aws k8s-aws -y
```

Or by hand: `kubeadm reset -f` on workers then control plane, then [Lesson AWS-15](./aws.md#lesson-aws-15-teardown).
