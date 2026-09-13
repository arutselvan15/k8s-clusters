# OpenStack — compute checklist

**Goal:** Ubuntu VMs on an existing Neutron net you can SSH to. Kubernetes is a **separate** doc: [kubeadm.md](../../../../docs/infra/kubeadm.md) (`./scripts/infra/kubeadm/up.sh openstack k8s-ocp`). Not Magnum/OpenShift.

Learning notes (compute): [docs/infra/openstack.md](../../../../docs/infra/openstack.md).

**Apply:** from `k8s-clusters/`

```bash
./scripts/infra/up.sh openstack k8s-ocp
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
```

**Config:** `sensitive/openstack/clouds.yaml` (Keystone auth) and `clusters/openstack/<id>/config.yaml` (image, flavor, existing `network_name`).  
**Code:** [`main.tf`](./main.tf).  
**Tear down:** `./scripts/infra/down.sh openstack k8s-ocp -y`

This cloud is **not** like AWS VPC: the project already has `tenant-internal-direct-net`. Terraform **looks up** that network and puts VMs on it. It does **not** create a network, subnet, or router. Optional **Octavia** LBs are the `octavia_lbs` list in the cluster YAML.

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
| [8](#step-8--optional-octavia-ingress-lb) | One Octavia VIP for ingress-nginx | `lb.tf` if enabled |
| [9](#step-9--kubeadm) | Kubernetes on those VMs | `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` |

---

## Step 0 — Credentials and tools

**Learn:** OpenStack identity is Keystone. Auth lives in **clouds.yaml**, not in Terraform and not in git.

**Created:** Local files only.

```bash
mkdir -p sensitive/openstack
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/openstack/clouds.yaml
```

Edit `sensitive/openstack/clouds.yaml`: `auth_url`, username/password **or** application credentials, `project_name`, `region_name`.  
Edit `clusters/openstack/k8s-ocp/config.yaml`: `image_name`, `node_flavor`, `network_name` (existing Neutron network, e.g. `tenant-internal-direct-net`).

If the OpenStack CLI is installed:

```bash
export OS_CLIENT_CONFIG_FILE=$PWD/sensitive/openstack/clouds.yaml OS_CLOUD=openstack
openstack image list
openstack flavor list
openstack network list
```

Pick an Ubuntu image, a flavor with ~2–4 vCPU / 8 GiB RAM, and the **existing** tenant network to attach to (not a new one).

**CodeGuard:** never commit `clouds.yaml` or paste passwords into chat.

---

## Step 1 — Terraform can talk to OpenStack

**Learn:** Provider reads `OS_CLIENT_CONFIG_FILE` + `cloud:` (from `clusters/openstack/k8s-ocp/config.yaml`). `data` asks Keystone/Glance/Neutron; `resource` creates objects you pay for (VMs, floating IPs).

**Created:** No extra quota yet. Data sources: auth scope, image, flavor, existing network.

**Outputs:** `project_id`, `project_name`, `user_name`

**Check:** `./scripts/infra/up.sh openstack k8s-ocp` (first apply creates the rest of the stack in later steps — this environment is one apply, like current `ec2`).

---

## Step 2 — Network

**Learn:** On cloud-rtp-1 the project already has a tenant network. Terraform **does not** create another (quota is typically 1). `network_name` in `clusters/openstack/k8s-ocp/config.yaml` is looked up as `data.openstack_networking_network_v2`.

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

User is **`ssh_user`** from config (`ubuntu` for Ubuntu images). Key: **`sensitive/openstack/k8s-ocp/ssh.pem`**.

```bash
ssh -i sensitive/openstack/k8s-ocp/ssh.pem ubuntu@$(terraform -chdir=infra/terraform/environments/openstack output -raw control_plane_public_ip)
```

---

## Step 6 — Worker VMs

`worker_nodes` in `clusters/openstack/k8s-ocp/config.yaml` (default 1). Each worker gets a port and instance on the same existing network. Names: `<cluster_name>-wk-1`, …

---

## Step 7 — SSH and outputs

```bash
terraform -chdir=infra/terraform/environments/openstack output
```

`./scripts/infra/up.sh openstack k8s-ocp` writes **`sensitive/openstack/k8s-ocp/cluster.env`** (gitignored) for kubeadm. No Terraform in the kubeadm scripts.

---

## Step 8 — Optional Octavia ingress LB

Set in `clusters/openstack/<id>/config.yaml`:

```yaml
  subnet_name: tenant-internal-direct-subnet7
  octavia_lb_flavor: Octavia_2vCPUx2GB
  octavia_lbs:
    - name: ingress
      http_node_port: 30080
      https_node_port: 30443
```

`subnet_name` is required when `octavia_lbs` is non-empty because the tenant network has multiple subnets. Each list item is one VIP (TCP 80 and 443) and uses **one** load-balancer quota. `octavia_lbs: []` skips Octavia. OpenStack quota still caps how many apply can create. Same NodePorts = several VIPs to the same ingress-nginx. Outputs: `octavia_lb_vips`, `ingress_lb_vip` if a name is `ingress`. Install ingress-nginx as **NodePort** with matching ports.

Debug CLI: [openstack.md](../../../../docs/infra/openstack.md#cli-cheat-sheet-debug).

---

## Step 9 — kubeadm

Same scripts as AWS. Point at the OpenStack inventory:

```bash
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
kubectl get nodes -o wide
```

Reset Kubernetes only: `./scripts/infra/kubeadm/reset.sh openstack k8s-ocp`  
Destroy VMs: `./scripts/infra/down.sh openstack k8s-ocp -y`

---

## Map

```text
Laptop  --SSH:22 / kubectl:6443-->  tenant-internal-direct-net (existing)
                                      |
                         |            |
                    control-plane   worker(s)
                    (kubeadm init)  (kubeadm join)
```
