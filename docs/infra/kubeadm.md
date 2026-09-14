# Kubernetes install (kubeadm)

**This doc is Kubernetes only.** It does **not** create, resize, or destroy VMs.

Compute and Kubernetes are **independent**:

| Layer | Owns | Command | Does not |
|-------|------|---------|----------|
| **Compute** | VMs, SSH, inventory | `./scripts/infra/up.sh aws k8s-aws` — [aws.md](./aws.md) | install kubelet, etcd, or the API |
| **Kubernetes** | kubeadm, CNI, kubeconfig | `./scripts/infra/kubeadm/up.sh aws k8s-aws` (this doc) | run Terraform or change EC2 |

You can create VMs and stop. You can install Kubernetes later on the same inventory. You can `kubeadm reset` and keep the VMs. You can destroy VMs without resetting Kubernetes first (the API is gone with the instances).

The same kubeadm scripts work on **OpenStack** VMs (`./scripts/infra/kubeadm/up.sh openstack k8s-ocp`). The cloud only matters for how you got SSH + `cluster.env`.

**Need:** SSH to the control plane and `sensitive/<env>/<cluster_name>/cluster.env` from compute (`./scripts/infra/up.sh …`).

## Automated

```bash
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

kubeadm SSHs using the inventory and streams [`scripts/infra/kubeadm/remote/`](../../scripts/infra/kubeadm/remote/) over stdin (no scp). Safe to re-run. It does not call Terraform.

Pod CIDR is `192.168.0.0/16` so it does **not** overlap the AWS VPC `10.0.0.0/16`.

Manual steps below are the CKA-style walkthrough (same commands as the remote scripts).

Pin one Kubernetes minor version on **every** node (`kubernetes_version` in `clusters/aws/k8s-aws/config.yaml`, default **1.32** — check [pkgs.k8s.io](https://pkgs.k8s.io) for current patch).

Use **`terraform output control_plane_public_ip`** (or the host in `cluster.env`) for the API endpoint. That IP came from compute; kubeadm only consumes it.

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
  # with cni: cilium, add --skip-phases=addon/kube-proxy

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

Save the **`kubeadm join`** command from init output. Do not paste the token into chat or git.

**Checkpoint:** Control plane node registered (still **NotReady** — no pod network yet).

---

## Lesson K-3 — Pod network

Nodes stay **NotReady** until a CNI runs. `cni` in the cluster YAML picks which one — see [cilium.md](../cilium.md) for the trade-off. Below is the control-plane view; `kubeadm/up.sh` instead runs these from the laptop once it has the kubeconfig, so only the laptop needs Helm.

```bash
# cni: calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml

# cni: cilium — kubeProxyReplacement needs the API endpoint directly, since
# skipping the kube-proxy addon left no ClusterIP path to reach it.
helm repo add cilium https://helm.cilium.io && helm repo update cilium
helm upgrade --install cilium cilium/cilium --version 1.17.18 -n kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${CP_PUBLIC}" --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set routingMode=tunnel --set tunnelProtocol=vxlan \
  --set loadBalancer.mode=snat \
  --set operator.replicas=1 \
  --set hubble.relay.enabled=true --set hubble.ui.enabled=true
```

**Checkpoint:** Control plane node **Ready**.

---

## Lesson K-4 — Join worker

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

## Lesson K-5 — kubeconfig on Mac

From repo root on your Mac:

```bash
ssh -i sensitive/aws/k8s-aws/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/ec2 output -raw control_plane_public_ip) \
  'sudo cat /etc/kubernetes/admin.conf' > sensitive/aws/k8s-aws/kubeconfig
chmod 600 sensitive/aws/k8s-aws/kubeconfig
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

`admin.conf` already has `https://<public-ip>:6443` because of `--control-plane-endpoint`.

Cloud `LoadBalancer` Services need a cloud controller (AWS CCM is not in this repo yet). That is still a compute/cloud concern, not kubeadm.

---

## CKA drills (same cluster)

Practice in namespace `cka-practice`: taints, drains, NetworkPolicy, RBAC, PV/PVC. Don't break the control-plane namespace.

---

## Reset Kubernetes (keep compute)

Does **not** destroy EC2:

```bash
./scripts/infra/kubeadm/reset.sh aws k8s-aws
```

Or by hand: `kubeadm reset -f` on workers then control plane.

Destroy VMs (compute, independent): [Lesson AWS-15](./aws.md#lesson-aws-15-teardown) / `./scripts/infra/down.sh aws k8s-aws -y`.
