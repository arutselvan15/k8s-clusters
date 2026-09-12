# AWS + Terraform learning path (aws-dev)

**Goal:** Build AWS infrastructure with **Terraform**, then **kubeadm on 2 EC2s** ([10-aws-kubeadm-cluster.md](./10-aws-kubeadm-cluster.md)), then this repo’s **Day 1–2** ([11-aws-platform-gitops.md](./11-aws-platform-gitops.md)).

**Kind `dev`** stays your free local lab. **`aws-dev`** is the cloud profile.

**Terraform (start here):**

- Guide: [infra/terraform/aws-kubeadm/README.md](../infra/terraform/aws-kubeadm/README.md)
- Root module: [environments/aws-dev/main.tf](../infra/terraform/aws-kubeadm/environments/aws-dev/main.tf)
- Variables example: [terraform.tfvars.example](../infra/terraform/aws-kubeadm/environments/aws-dev/terraform.tfvars.example)

Shell working directory for all `terraform` commands:

```text
infra/terraform/aws-kubeadm/environments/aws-dev/
```

---

## Lesson checklist

| Lesson | Done |
|--------|------|
| [AWS-0](#lesson-aws-0) Account & CLI | ☐ |
| [AWS-1](#lesson-aws-1) Terraform init | ☐ |
| [AWS-2](#lesson-aws-2) VPC | ☐ |
| [AWS-3](#lesson-aws-3) Subnet + IGW | ☐ |
| [AWS-4](#lesson-aws-4) Security groups | ☐ |
| [AWS-5](#lesson-aws-5) Control plane EC2 | ☐ |
| [AWS-6](#lesson-aws-6) Worker EC2 | ☐ |
| [AWS-7](#lesson-aws-7) Outputs & SSH | ☐ |
| [K-1–K-4](./10-aws-kubeadm-cluster.md) kubeadm cluster | ☐ |
| [P-1–P-3](./11-aws-platform-gitops.md) Platform GitOps | ☐ |
| [AWS-15](#lesson-aws-15) Teardown | ☐ |

---

<a id="lesson-aws-0"></a>

## Lesson AWS-0 — AWS account and CLI

**Learn:** Regions, IAM identity, never commit access keys.

1. Pick one **region** (e.g. `us-east-1`) and use it everywhere.
2. Create an **IAM user** (or SSO) with programmatic access for labs—not root.
3. Attach a **least-privilege policy** for this lab (e.g. `AmazonEC2FullAccess` for learning only; tighten later).
4. Install AWS CLI v2: `brew install awscli`
5. Configure:

   ```bash
   aws configure
   aws sts get-caller-identity
   ```

6. Install Terraform: `brew install terraform`

**Checkpoint:** `aws sts get-caller-identity` returns your account ID.

**Cost:** $0 until you create EC2.

---

<a id="lesson-aws-1"></a>

## Lesson AWS-1 — Terraform init

**Learn:** Provider, working directory, local state.

```bash
cd infra/terraform/aws-kubeadm/environments/aws-dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
admin_cidr = "YOUR.PUBLIC.IP/32"
```

Get your IP: `curl -s ifconfig.me` then add `/32`.

```bash
terraform init
terraform validate
```

Read:

- [versions.tf](../infra/terraform/aws-kubeadm/environments/aws-dev/versions.tf)
- [variables.tf](../infra/terraform/aws-kubeadm/environments/aws-dev/variables.tf)

**Checkpoint:** `terraform validate` succeeds.

---

<a id="lesson-aws-2"></a>

## Lesson AWS-2 — VPC only

**Learn:** A **VPC** is your private network in AWS (CIDR block).

**Console:** VPC → Your VPCs (after apply).

Incremental apply (optional):

```bash
terraform apply -target=module.network.aws_vpc.this
```

Or apply the full stack when ready (Lesson AWS-7).

**File:** [modules/network/main.tf](../infra/terraform/aws-kubeadm/modules/network/main.tf) (`aws_vpc`).

**Verify:**

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=aws-dev-vpc"
```

**Checkpoint:** What CIDR did you choose and why?

---

<a id="lesson-aws-3"></a>

## Lesson AWS-3 — Subnet and internet

**Learn:** **Subnet** = slice of VPC in one AZ. **Internet Gateway** + route `0.0.0.0/0` = public reachability.

**Resources:** `aws_subnet.public`, `aws_internet_gateway`, `aws_route_table`.

```bash
terraform apply -target=module.network
```

**Console:** VPC → Subnets → route table with `0.0.0.0/0` → igw.

**Checkpoint:** Why is `map_public_ip_on_launch = true` needed for a simple lab?

---

<a id="lesson-aws-4"></a>

## Lesson AWS-4 — Security groups

**Learn:** **Security groups** are stateful firewalls on ENIs. Restrict **22** and **6443** to **your IP only**.

```bash
terraform apply -target=module.security
```

**File:** [modules/security/main.tf](../infra/terraform/aws-kubeadm/modules/security/main.tf)

**Console:** EC2 → Security Groups → `aws-dev-cp` / `aws-dev-worker`.

**Checkpoint:** Why is 6443 only on the control plane SG?

---

<a id="lesson-aws-5"></a>

## Lesson AWS-5 — Control plane EC2

**Learn:** EC2 instance, key pair, **Elastic IP** (stable API endpoint).

In `terraform.tfvars`:

```hcl
create_worker = false
```

```bash
terraform apply
```

**Verify:**

```bash
terraform output ssh_cp_command
# run the ssh command — Ubuntu welcome
```

**Cost:** ~t3.medium + EIP while running.

**Checkpoint:** SSH works; `curl -k https://<eip>:6443` fails (no API yet).

---

<a id="lesson-aws-6"></a>

## Lesson AWS-6 — Worker EC2

In `terraform.tfvars`:

```hcl
create_worker = true
```

```bash
terraform apply
```

**Verify:** Two instances in EC2 console; worker has a public IP (ephemeral) or use private IP from CP for ping tests.

**Checkpoint:** Both instances in the same subnet and SG rules allow CP ↔ worker.

---

<a id="lesson-aws-7"></a>

## Lesson AWS-7 — Outputs and SSH

```bash
terraform output
terraform output kubeadm_control_plane_endpoint
```

Save:

- `control_plane_public_ip`
- `ssh_private_key_path` (under [environments/aws-dev/.ssh/](../infra/terraform/aws-kubeadm/environments/aws-dev/.ssh/), gitignored `*.pem`)
- `kubeadm_control_plane_endpoint`

**Next:** [10-aws-kubeadm-cluster.md](./10-aws-kubeadm-cluster.md) — Lessons **K-1** through **K-4**.

---

<a id="lesson-aws-15"></a>

## Lesson AWS-15 — Teardown

**Before destroy:** If you already installed Kubernetes, on nodes run `kubeadm reset` (see [10-aws-kubeadm-cluster.md](./10-aws-kubeadm-cluster.md)).

```bash
cd infra/terraform/aws-kubeadm/environments/aws-dev
terraform destroy
```

**Console:** No EC2, no EIP, no VPC named `aws-dev-*`.

**Cost:** Should drop to $0 for this lab (verify Billing dashboard).

---

## Incremental apply reference

| Lesson | Optional command |
|--------|------------------|
| AWS-2 | `terraform apply -target=module.network.aws_vpc.this` |
| AWS-3 | `terraform apply -target=module.network` |
| AWS-4 | `terraform apply -target=module.security` |
| AWS-5–7 | `terraform apply` (with `create_worker` toggled) |

Full `terraform apply` is fine once you understand the modules.

---

## If your IP changes

Update `admin_cidr` in `terraform.tfvars` and run `terraform apply` so SSH and `kubectl` to `:6443` work again.
