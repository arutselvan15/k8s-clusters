# Day 0 — AWS (Terraform)

**Goal:** Create EC2 VMs with **Terraform**, then install Kubernetes with **kubeadm** ([aws-kubeadm.md](./aws-kubeadm.md)). After nodes are Ready, use the **same** [bootstrap](../bootstrap/) and [gitops](../gitops/) as Kind.

This is one Day 0 environment. It is not a separate platform.

Prefer the dispatcher over raw `terraform` once credentials exist:

```bash
./scripts/infra/up.sh aws default
./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-aws/kubeconfig
```

- Checklist (why each object exists): [infra/terraform/environments/ec2/STEPS.md](../../infra/terraform/environments/ec2/STEPS.md)
- Root module: [environments/ec2/main.tf](../../infra/terraform/environments/ec2/main.tf)
- Lab settings: [default.yaml.example](../../config/aws/clusters/default.yaml.example); AWS region: [cli.conf](../../config/aws/cli.conf.example); keys: `config/aws/credentials`

Working directory if you run Terraform by hand:

```text
infra/terraform/environments/ec2/
```

---

## Lesson checklist

| Lesson | Done |
|--------|------|
| [AWS-0](#lesson-aws-0) Account & CLI | ☐ |
| [AWS-1](#lesson-aws-1) Terraform talks to AWS | ☐ |
| [AWS-2](#lesson-aws-2) VPC | ☐ |
| [AWS-3](#lesson-aws-3) Subnet + IGW | ☐ |
| [AWS-4](#lesson-aws-4) Security groups | ☐ |
| [AWS-5](#lesson-aws-5) Control plane EC2 | ☐ |
| [AWS-6](#lesson-aws-6) Worker EC2 | ☐ |
| [AWS-7](#lesson-aws-7) Outputs & SSH | ☐ |
| [K-1–K-4](./aws-kubeadm.md) kubeadm cluster | ☐ |
| Common Day 1–2 ([bootstrap](../bootstrap/) · [gitops](../gitops/)) | ☐ |
| [AWS-15](#lesson-aws-15) Teardown | ☐ |

The current `main.tf` applies **all** of AWS-1–7 in one `./scripts/infra/up.sh aws default`. Read STEPS.md as you go so you still learn each object. Incremental `-target` is optional.

---

<a id="lesson-aws-0"></a>

## Lesson AWS-0 — AWS account and CLI

**Learn:** Regions, IAM identity, never commit access keys.

1. Pick one **region** (e.g. `us-east-1`) and use it everywhere.
2. Create an **IAM user** (or SSO) with programmatic access for labs—not root.
3. Attach a **least-privilege policy** for this lab (e.g. `AmazonEC2FullAccess` for learning only; tighten later).
4. Install AWS CLI v2: `brew install awscli`
5. Copy project credentials (gitignored):

   ```bash
   cp config/aws/credentials.example config/aws/credentials
   cp config/aws/cli.conf.example config/aws/cli.conf
   cp config/aws/clusters/default.yaml.example config/aws/clusters/default.yaml
   chmod 600 config/aws/credentials
   ```

   Fill keys in `config/aws/credentials`. Set `admin_cidr` in `config/aws/clusters/default.yaml` to `YOUR.PUBLIC.IP/32` when you leave the wide-open lab default.

6. Install Terraform: `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`

**Checkpoint:** `./scripts/infra/aws/up.sh` prints `aws sts get-caller-identity` (or run that after sourcing project env).

**Cost:** $0 until you create EC2.

---

<a id="lesson-aws-1"></a>

## Lesson AWS-1 — Terraform can talk to AWS

**Learn:** Provider, working directory, local state. `data` = ask AWS; `resource` = create something you pay to keep.

```bash
./scripts/infra/up.sh aws
```

Or by hand:

```bash
cd infra/terraform/environments/ec2
terraform init
terraform validate
```

Read:

- [versions.tf](../../infra/terraform/environments/ec2/versions.tf)
- [variables.tf](../../infra/terraform/environments/ec2/variables.tf)

Provider reads `k8s-platform/config/aws/` (not `~/.aws`).

**Checkpoint:** `terraform output account_id` / `caller_arn` after the first apply.

---

<a id="lesson-aws-2"></a>

## Lesson AWS-2 — VPC

**Learn:** A **VPC** is your private network in AWS (CIDR block). Default lab CIDR is `10.0.0.0/16` (`vpc_cidr` in `config/aws/clusters/default.yaml`).

**File:** [main.tf](../../infra/terraform/environments/ec2/main.tf) (`aws_vpc.lab`).

**Verify:**

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-aws-vpc"
```

Details: [STEPS.md Step 2](../../infra/terraform/environments/ec2/STEPS.md#step-2--vpc).

---

<a id="lesson-aws-3"></a>

## Lesson AWS-3 — Subnet and internet

**Learn:** **Subnet** = slice of VPC in one AZ. **Internet Gateway** + route `0.0.0.0/0` = public reachability. `map_public_ip_on_launch = true` so lab EC2s get a public IPv4.

**Checkpoint:** Why is that flag needed for SSH from your laptop?

---

<a id="lesson-aws-4"></a>

## Lesson AWS-4 — Security groups

**Learn:** **Security groups** are stateful firewalls on ENIs. Lab opens **22** and **6443** to `admin_cidr`, plus `self` for node-to-node.

Tighten `admin_cidr` to your IP `/32` before anything other than a throwaway lab.

---

<a id="lesson-aws-5"></a>

## Lesson AWS-5 — Control plane EC2

**Learn:** EC2 instance + generated ED25519 key pair. Until kubeadm, this is only Ubuntu.

```bash
terraform -chdir=infra/terraform/environments/ec2 output ssh_control_plane
```

PEM: `clusters/aws/ssh.pem` (gitignored). User: `ubuntu`.

**Cost:** ~t3.medium + disk + public IPv4 while running.

**Checkpoint:** SSH works; `curl -k https://<public-ip>:6443` fails (no API yet).

---

<a id="lesson-aws-6"></a>

## Lesson AWS-6 — Worker EC2

`worker_nodes` in `config/aws/clusters/default.yaml` (default 1). Extra VMs are `k8s-aws-worker-2`, … First worker stays `aws_instance.worker` so state is not replaced.

**Checkpoint:** Both instances in the same subnet; SG `self` allows CP ↔ worker.

---

<a id="lesson-aws-7"></a>

## Lesson AWS-7 — Outputs and SSH

```bash
terraform -chdir=infra/terraform/environments/ec2 output
```

`aws/up.sh` writes `clusters/aws/cluster.env` (gitignored) for kubeadm.

**Next:** [aws-kubeadm.md](./aws-kubeadm.md) — automated `./scripts/infra/kubeadm/up.sh` or manual K-1–K-4. Then [bootstrap](../bootstrap/) and [gitops](../gitops/).

---

<a id="lesson-aws-15"></a>

## Lesson AWS-15 — Teardown

Kubernetes only (keep VMs): `./scripts/infra/kubeadm/reset.sh`

Then:

```bash
./scripts/infra/down.sh aws -y
```

**Console:** No EC2, no VPC named `k8s-aws-*`.

**Cost:** Should drop to $0 for this lab (verify Billing dashboard).

---

## If your IP changes

Update `admin_cidr` in `config/aws/clusters/default.yaml` and re-run `./scripts/infra/up.sh aws default` so SSH and `kubectl` to `:6443` work again.
