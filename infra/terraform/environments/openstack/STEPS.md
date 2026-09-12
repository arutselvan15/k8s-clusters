# OpenStack + kubeadm — step checklist

**Goal:** Same as [ec2](../ec2/STEPS.md): Ubuntu VMs you install with kubeadm. Kind stays the local lab; AWS stays the other cloud. Kubernetes is **not** Magnum/OpenShift — it is the same `./scripts/infra/kubeadm/up.sh` after Terraform writes an inventory.

Learning notes: [docs/infra/openstack.md](../../../../docs/infra/openstack.md). Then common [bootstrap](../../../../docs/bootstrap/) and [gitops](../../../../docs/gitops/).

**Apply:** from `k8s-platform/`

```bash
./scripts/infra/up.sh openstack default
# or: ./scripts/infra/openstack/up.sh default
./scripts/infra/kubeadm/up.sh default
```

**Config:** `config/openstack/clouds.yaml` (Keystone auth, gitignored) and `config/openstack/clusters/<id>.yaml` (image, flavor, existing `network_name`).  
**Code:** [`main.tf`](./main.tf).  
**Tear down:** `./scripts/infra/openstack/down.sh default -y`

This cloud is **not** like AWS VPC: the project already has `tenant-internal-direct-net`. Terraform **looks up** that network and puts VMs on it. It does **not** create a network, subnet, router, or floating IP (those quotas are already used).

AWS name → OpenStack name: existing tenant net (not a new VPC), security group → Neutron **secgroup**, EC2 → Nova **instance**. SSH uses the instance **fixed IP** on that net (reachable if you are on the Cisco network).

---

## Checklist

| Step | What you create | Status |
|------|-----------------|--------|
| [0](#step-0--credentials-and-tools) | Local clouds.yaml + config | you fill |
| [1](#step-1--terraform-can-talk-to-openstack) | Nothing — read project/user | you apply |
| [2](#step-2--network) | Use existing `tenant-internal-direct-net` | lookup only |
| [3](#step-3--subnet--router) | Not created (already on that net) | skipped |
| [4](#step-4--security-group) | SSH 22, API 6443, node-to-node | in main.tf |
| [5](#step-5--control-plane-vm) | Ubuntu VM on existing net + SSH | in main.tf |
| [6](#step-6--worker-vms) | `worker_nodes` Ubuntu VMs | in main.tf |
| [7](#step-7--ssh-and-outputs) | PEM, fixed IPs, inventory | in main.tf |
| [8](#step-8--kubeadm) | Same kubeadm scripts as AWS | `./scripts/infra/kubeadm/up.sh default` |

---

## Step 0 — Credentials and tools

**Learn:** OpenStack identity is Keystone. Auth lives in **clouds.yaml**, not in Terraform and not in git.

**Created:** Local files only.

```bash
cp config/openstack/clouds.yaml.example config/openstack/clouds.yaml
cp config/openstack/clusters/default.yaml.example config/openstack/clusters/default.yaml
chmod 600 config/openstack/clouds.yaml
```

Edit `clouds.yaml`: `auth_url`, username/password **or** application credentials, `project_name`, `region_name`.  
Edit `config/openstack/clusters/default.yaml`: `image_name`, `node_flavor`, `network_name` (existing Neutron network, e.g. `tenant-internal-direct-net`).

If the OpenStack CLI is installed:

```bash
export OS_CLIENT_CONFIG_FILE=$PWD/config/openstack/clouds.yaml OS_CLOUD=lab
openstack image list
openstack flavor list
openstack network list
```

Pick an Ubuntu image, a flavor with ~2–4 vCPU / 8 GiB RAM, and the **existing** tenant network to attach to (not a new one).

**CodeGuard:** never commit `clouds.yaml` or paste passwords into chat.

---

## Step 1 — Terraform can talk to OpenStack

**Learn:** Provider reads `OS_CLIENT_CONFIG_FILE` + `cloud:` (from `config/openstack/clusters/default.yaml`). `data` asks Keystone/Glance/Neutron; `resource` creates objects you pay for (VMs, floating IPs).

**Created:** No extra quota yet. Data sources: auth scope, image, flavor, existing network.

**Outputs:** `project_id`, `project_name`, `user_name`

**Check:** `./scripts/infra/openstack/up.sh` (first apply creates the rest of the stack in later steps — this environment is one apply, like current `ec2`).

---

## Step 2 — Network

**Learn:** On cloud-rtp-1 the project already has a tenant network. Terraform **does not** create another (quota is typically 1). `network_name` in `config/openstack/clusters/default.yaml` is looked up as `data.openstack_networking_network_v2`.

**Created:** nothing. Uses `tenant-internal-direct-net`.

---

## Step 3 — Subnet + router

**Skipped.** Subnet and router already exist for that tenant network. No floating IPs.

---

## Step 4 — Security group

Same intent as AWS:

| Rule | From | Why |
|------|------|-----|
| TCP 22 | `admin_cidr` | SSH |
| TCP 6443 | `admin_cidr` | kubectl after kubeadm |
| All | same secgroup | control-plane ↔ workers |
| Egress | default allow | packages, images |

---

## Step 5 — Control-plane VM

**Learn:** Nova instance, boot **volume**. The port sits on `tenant-internal-direct-net`. The address your laptop SSHs to is that **fixed IP** (no floating IP). You need to be on a network that can reach that tenant net (typical on Cisco campus/VPN).

User is **`ssh_user`** from config (`ubuntu` for Ubuntu images). Key: **`clusters/k8s-os/ssh.pem`**.

```bash
ssh -i clusters/k8s-os/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/openstack output -raw control_plane_public_ip)
```

---

## Step 6 — Worker VMs

`worker_nodes` in `config/openstack/clusters/default.yaml` (default 1). Each worker gets a port and instance on the same existing network. Names: `<cluster_name>-<worker_prefix>-1`, …

---

## Step 7 — SSH and outputs

```bash
terraform -chdir=infra/terraform/environments/openstack output
```

`./scripts/infra/openstack/up.sh` writes **`clusters/k8s-os/cluster.env`** (gitignored) for kubeadm. No Terraform in the kubeadm scripts.

---

## Step 8 — kubeadm

Same scripts as AWS. Point at the OpenStack inventory:

```bash
./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-os/kubeconfig
kubectl get nodes -o wide
```

Reset Kubernetes only: `./scripts/infra/kubeadm/reset.sh default`  
Destroy VMs: `./scripts/infra/openstack/down.sh default -y`

---

## Map

```text
Laptop  --SSH:22 / kubectl:6443-->  tenant-internal-direct-net (existing)
                                      |
                         |            |
                    control-plane   worker(s)
                    (kubeadm init)  (kubeadm join)
```
