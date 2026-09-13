# AWS EC2 + kubeadm — step checklist

**Goal:** A small Kubernetes cluster on EC2 that you install yourself with kubeadm (not EKS). Kind stays the free local lab.

Learning notes: [docs/infra/aws.md](../../../../docs/infra/aws.md) → [aws-kubeadm.md](../../../../docs/infra/aws-kubeadm.md). Then [k8s-gitops](../../../../../k8s-gitops).

**Apply (every Terraform step):** from `k8s-platform/`

```bash
./scripts/infra/up.sh aws k8s-aws
# after VMs exist: ./scripts/infra/kubeadm/up.sh aws k8s-aws
```

**Config:** `sensitive/aws/credentials` (keys), `sensitive/aws/cli.conf` (region), `clusters/aws/<id>/config.yaml` (cluster knobs).  
**Code:** [`main.tf`](./main.tf) in this directory.  
**Tear down:** `./scripts/infra/down.sh aws k8s-aws -y`

---

## Checklist

| Step | What you create | Cost | Status |
|------|-----------------|------|--------|
| [0](#step-0--credentials-and-tools) | Nothing in AWS — IAM keys + CLI on the laptop | $0 | done |
| [1](#step-1--terraform-can-talk-to-aws) | Nothing — Terraform *reads* account/region | $0 | done |
| [2](#step-2--vpc) | One VPC (`k8s-aws-vpc`, `10.0.0.0/16`) | $0 | done |
| [3](#step-3--subnet--internet-gateway) | Public subnet + IGW + route to internet | $0 | done |
| [4](#step-4--security-group) | Firewall: SSH + Kubernetes API | $0 | done |
| [5](#step-5--control-plane-ec2) | One Ubuntu VM + [SSH](#ssh-to-the-node) | EC2 hourly | done |
| [6](#step-6--worker-ec2) | One Ubuntu VM (kubelet / pods) | EC2 hourly | done |
| [7](#step-7--ssh-and-outputs) | SSH key, public IPs, how to log in | tiny (IPv4) | done |
| [8](#step-8--kubeadm) | Kubernetes on those VMs; kubeconfig | included | `./scripts/infra/kubeadm/up.sh aws k8s-aws` |

Update the **Status** column when you finish a step. Summaries below stay as the “why” for later.

---

## Step 0 — Credentials and tools

**Learn:** AWS identity is not Kubernetes. Keys never go in git or in Terraform.

**Created:** Local files only.

- `sensitive/aws/credentials` — access key + secret (gitignored)
- `sensitive/aws/cli.conf` — `region` (gitignored)
- `clusters/aws/k8s-aws/config.yaml` — cluster knobs (`cluster_name`, `vpc_cidr`, …) (committed)

**Check:** `./scripts/infra/up.sh aws k8s-aws` prints `aws sts get-caller-identity` (account id + IAM ARN).

---

## Step 1 — Terraform can talk to AWS

**Learn:** `data` = ask AWS a question. `resource` = create something you pay to keep. Provider reads `sensitive/aws/` (not `~/.aws`).

**Created:** No AWS objects. Two data sources in [`main.tf`](./main.tf):

- `aws_caller_identity` — who the keys belong to
- `aws_region` — `us-east-1`

**Outputs:** `account_id`, `caller_arn`

**Check:** `terraform output` in this directory shows your ARN. State file exists; resource count is still 0.

---

## Step 2 — VPC

**Learn:** A **VPC** is a private IPv4 network in your account. It is not a VM and not the internet. Everything later (subnet, EC2, Kubernetes node IPs) lives inside this CIDR.

**Created:**

| AWS object | Name / value | Role |
|------------|----------------|------|
| VPC | tag `Name=k8s-aws-vpc` | Fence around `10.0.0.0/16` |
| DNS on VPC | `enable_dns_hostnames` | Instances can get DNS names later |

**Not created yet (at the time we wrote Step 2):** subnet, internet gateway, route table, security group, EC2. Step 3 adds the first three.

**Outputs:** `vpc_id` (`vpc-…`), `vpc_cidr`

**Check:**

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-aws-vpc" \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock}' --output table
```

Console: **VPC → Your VPCs → k8s-aws-vpc**.

---

## Step 3 — Subnet + internet gateway

**Learn:** A VPC has no “streets” until you add a **subnet** (slice of the CIDR in one Availability Zone). An **internet gateway (IGW)** is attached to the VPC and is the door to the public internet. A **route** `0.0.0.0/0 → IGW` on a route table, **associated** to the subnet, makes that subnet public. `map_public_ip_on_launch` means a future EC2 in this subnet gets a public IPv4 automatically.

`cidrsubnet(10.0.0.0/16, 8, 1)` takes 8 extra bits from the host part → `/24` networks, and picks index `1` → **`10.0.1.0/24`**.

**Created:**

| AWS object | Name / value | Role |
|------------|----------------|------|
| Subnet | `k8s-aws-public`, `10.0.1.0/24`, first AZ | Where EC2 will live |
| Internet gateway | `k8s-aws-igw` | VPC ↔ internet |
| Route table | `k8s-aws-public`, route `0.0.0.0/0 → IGW` | “How to leave this subnet” |
| Route table association | subnet ↔ that table | Makes *this* subnet use that route |

**Not created yet:** security group, EC2, Elastic IP (the instance public IP comes in Step 5).

**Outputs:** `subnet_id`, `subnet_cidr`, `availability_zone`, `internet_gateway_id`

**Check:**

```bash
terraform -chdir=infra/terraform/environments/ec2 output
aws ec2 describe-subnets --filters "Name=tag:Name,Values=k8s-aws-public" \
  --query 'Subnets[].{Id:SubnetId,Cidr:CidrBlock,Az:AvailabilityZone}' --output table
```

Console: **VPC → Subnets → k8s-aws-public**, **Internet gateways → k8s-aws-igw**, **Route tables** (look for `0.0.0.0/0` target `igw-…`).

**Will not create:** EC2 (still no computer).

---

## Step 4 — Security group

**Learn:** A **security group** is a stateful firewall on the instance network interface (ENI). Default inbound is **deny**. Egress we allow all so the VM can `apt` and pull images. It is **not** attached to anything until Step 5 (EC2 references this SG).

`admin_cidr` comes from `clusters/aws/k8s-aws/config.yaml`. Lab value `0.0.0.0/0` means any internet host can try SSH and `:6443` — fine for learning, tighten to `YOUR.IP/32` later.

**Created:**

| Rule | From | Why |
|------|------|-----|
| TCP 22 | `admin_cidr` | SSH from your laptop |
| TCP 6443 | `admin_cidr` | `kubectl` to the API (after kubeadm) |
| All protocols | same SG (`self`) | Control plane ↔ worker (kubelet 10250, CNI, API on the private IP) |
| All outbound | `0.0.0.0/0` | Install packages, pull images |

**Not created yet:** EC2 (the SG is an empty rule set until a VM uses it).

**Outputs:** `security_group_id` (`sg-…`), `admin_cidr`

**Check:**

```bash
terraform -chdir=infra/terraform/environments/ec2 output security_group_id
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=k8s-aws-sg" \
  --query 'SecurityGroups[].{Id:GroupId,Ingress:IpPermissions}' --output json
```

Console: **VPC → Security groups → k8s-aws-sg**.

---

## Step 5 — Control-plane EC2

**Learn:** This VM *will be* the Kubernetes control plane after kubeadm (API server, etcd, scheduler). Right now it is only **Ubuntu 22.04**. Terraform does not install Kubernetes yet.

**Cost starts here:** `t3.medium` ~$0.04/hour + 20 GiB gp3 + a public IPv4 (~$0.005/hour). Destroy with `./scripts/infra/down.sh aws k8s-aws -y` when you stop for the day.

**Created:**

| AWS / local object | Name / value | Role |
|--------------------|----------------|------|
| AMI lookup | Ubuntu 22.04 amd64 (Canonical) | Disk image |
| TLS key (ED25519) | private file gitignored | SSH identity |
| Key pair | `k8s-aws-ssh` in AWS | Public half of that key |
| Local PEM | `sensitive/aws/k8s-aws/ssh.pem` mode `0600` | What you pass to `ssh -i` |
| EC2 | `k8s-aws-cp`, `t3.medium` | The VM, in the public subnet, SG attached, public IP |

**Not created yet:** worker VM, kubeadm, kubeconfig.

**Outputs:** `control_plane_public_ip`, `control_plane_private_ip`, `ssh_private_key_path`, `ssh_control_plane`

### SSH to the node

User is **`ubuntu`** (Ubuntu AMI). The private key is **`sensitive/aws/k8s-aws/ssh.pem`** (gitignored). Do not commit it or paste it into chat.

From `k8s-platform/`:

```bash
# 1. Instance must be Running (wait ~30s after apply)
terraform -chdir=infra/terraform/environments/ec2 output

# 2. Copy the ssh_control_plane value and run it, or:
ssh -i sensitive/aws/k8s-aws/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/ec2 output -raw control_plane_public_ip)
```

First connect: type `yes` when asked to trust the host key. You should get an Ubuntu prompt (`ubuntu@ip-10-0-1-…`).

```bash
hostname
ip -4 addr show
exit
```

| Symptom | What to check |
|---------|----------------|
| `Permission denied (publickey)` | `chmod 600 sensitive/aws/k8s-aws/ssh.pem`; user is `ubuntu` not `ec2-user` or `root` |
| `Connection timed out` | Instance **Running**; security group TCP 22; use the **public** IP from `terraform output` |
| `UNPROTECTED PRIVATE KEY FILE` | `chmod 600 sensitive/aws/k8s-aws/ssh.pem` |

AWS console: **EC2 → Instances → k8s-aws-cp → Connect** is optional; this lab uses the PEM above, not EC2 Instance Connect.

---

## Step 6 — Worker EC2

**Learn:** This VM *will* run pods after `kubeadm join`. Right now it is a second Ubuntu box on the **same** subnet, security group, AMI, instance type, and SSH key as the control plane. They can already reach each other because of the SG `self` rule. Kubernetes is still not installed.

**Cost:** another `t3.medium` + disk + public IPv4 per worker. Default `worker_nodes = 1` in `clusters/aws/k8s-aws/config.yaml`. Extra VMs are `k8s-aws-wk-2`, … (`aws_instance.extra_workers`); the first worker stays `aws_instance.worker` so existing state is not replaced.

**Created:**

| AWS object | Name / value | Role |
|------------|----------------|------|
| EC2 | `k8s-aws-wk-1`, `t3.medium` | First worker (kubelet / pods) |
| EC2 (optional) | `k8s-aws-wk-N` when `worker_nodes` > 1 | More workers |

**Not created yet:** kubeadm, CNI, kubeconfig.

**Outputs:** `worker_public_ip` (first), `worker_public_ips` (all, space-separated), `ssh_worker`

### SSH to the worker

Same user and key as the control plane:

```bash
terraform -chdir=infra/terraform/environments/ec2 output ssh_worker

ssh -i sensitive/aws/k8s-aws/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/ec2 output -raw worker_public_ip)
```

From the control plane you can also ping the worker’s **private** IP (`terraform output worker_private_ip`, typically `10.0.1.x`).

**Check:** Console **EC2 → Instances** should show both `k8s-aws-cp` and `k8s-aws-wk-1` Running.

---

## Step 7 — SSH and outputs

- Control plane: [Step 5 SSH](#ssh-to-the-node)
- Worker: [Step 6 SSH](#ssh-to-the-worker)

```bash
terraform -chdir=infra/terraform/environments/ec2 output
```

---

## Step 8 — kubeadm

**Learn:** Terraform stopped at Ubuntu VMs. Kubernetes is a **separate** step: `kubeadm/up.sh` reads `sensitive/aws/k8s-aws/cluster.env` (written by `./scripts/infra/up.sh aws k8s-aws`), not Terraform. Same minor version on every node (`kubernetes_version` / `K8S_VERSION`). Pod CIDR is `192.168.0.0/16` so it does **not** overlap the VPC `10.0.0.0/16`. `WORKER_HOSTS` is a space-separated list (one or more workers).

**Created (after you finish):** kubeadm cluster; Calico CNI; `sensitive/aws/k8s-aws/kubeconfig` on the laptop.

No new AWS bill beyond the VMs.

From `k8s-platform/` (takes ~10–15 minutes; VMs must be Running; inventory must exist):

```bash
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

The script SSHs using the inventory (`SSH_USER`, `SSH_KEY`, hosts) and streams [`scripts/infra/kubeadm/remote/`](../../../../scripts/infra/kubeadm/remote/) over SSH stdin (nothing is copied onto the VMs). It is safe to re-run (skips init/join if already done). Manual copy-paste is below if you want to watch each command.

Inventory (gitignored; Day 0 writes it): `sensitive/aws/k8s-aws/cluster.env`. Template: [`scripts/infra/kubeadm/inventory.example`](../../../../scripts/infra/kubeadm/inventory.example). Extra workers: set `worker_nodes` in `clusters/aws/k8s-aws/config.yaml` and re-apply Terraform, then run `kubeadm/up.sh` again.

On the laptop, note the IPs (used as `--control-plane-endpoint` so kubectl from the Mac hits `:6443`):

```bash
cd k8s-platform
terraform -chdir=infra/terraform/environments/ec2 output control_plane_public_ip
terraform -chdir=infra/terraform/environments/ec2 output control_plane_private_ip
terraform -chdir=infra/terraform/environments/ec2 output worker_private_ip
```

SSH: [control plane](#ssh-to-the-node) and [worker](#ssh-to-the-worker).

### Manual (same as `scripts/infra/kubeadm/remote/`)

### 8a — Prepare both nodes

Run this **identically** on control plane **and** worker (`ubuntu`):

```bash
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
sudo sysctl --system

sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

K8S_VERSION=1.32
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
kubeadm version
```

**Checkpoint:** `kubeadm version` shows v1.32.x on both VMs.

### 8b — Init control plane only

On the **control plane**, replace `CP_PUBLIC` with `control_plane_public_ip` from Terraform:

```bash
CP_PUBLIC="<paste-control-plane-public-ip>"
sudo kubeadm init \
  --control-plane-endpoint="${CP_PUBLIC}:6443" \
  --apiserver-cert-extra-sans="${CP_PUBLIC}" \
  --pod-network-cidr=192.168.0.0/16

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml
kubectl get nodes
```

Copy the `kubeadm join ... --token ...` line from the init output and save it. Wait until the control-plane node is **Ready** (`kubectl get nodes`).

`--control-plane-endpoint` is the public IP so your **laptop** can `kubectl` on port 6443 (already open in the security group).

### 8c — Join the worker

On the **worker**, paste the join command from 8b:

```bash
sudo kubeadm join ...
```

On the **control plane**:

```bash
kubectl get nodes -o wide
```

**Checkpoint:** two nodes **Ready**. Worker INTERNAL-IP should be `10.0.1.x`.

### 8d — kubeconfig on the laptop

From `k8s-platform/` on the Mac (not inside SSH):

```bash
mkdir -p sensitive/aws/k8s-aws
ssh -i sensitive/aws/k8s-aws/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/ec2 output -raw control_plane_public_ip) \
  'sudo cat /etc/kubernetes/admin.conf' > sensitive/aws/k8s-aws/kubeconfig
chmod 600 sensitive/aws/k8s-aws/kubeconfig

source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes -o wide
```

`clusters/` outputs are gitignored. `admin.conf` already has `https://<public-ip>:6443` because of `--control-plane-endpoint`.

### Reset (before `infra/down.sh`)

Kubernetes only (keep the VMs):

```bash
./scripts/infra/kubeadm/reset.sh aws k8s-aws
```

Then destroy AWS: `./scripts/infra/down.sh aws k8s-aws -y`.

---

## Map (after all steps)

```text
Laptop  --SSH:22 / kubectl:6443-->  Internet
                                      |
                                   IGW (door)
                                      |
                         VPC 10.0.0.0/16  (fence)
                              |
                         public subnet
                         |            |
                    control-plane   worker
                    (kubeadm init)  (kubeadm join)
```

Kind is a different fence on your Mac (`environments/kind`). This file is only AWS EC2.
