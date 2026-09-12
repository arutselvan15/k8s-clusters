# Continue here — session context

Use this file when resuming work (solo or with an AI assistant). Paste or link: **“Read `knowledge/00-continue-context.md` and continue from Next steps.”**

Last updated from planning/build session: **2026-06-14** (approx.).

---

## Project goal

**k8s-platform** — learn platform engineering on:

1. **Kind on Mac** (`dev`) — Day 0–2 already working (Argo CD, ingress-nginx, cert-manager, Argo TLS).
2. **AWS** (`aws-dev`) — Terraform + **kubeadm on 2 EC2s** for CKA-style learning + same Day 1–2 pattern later.

Operational runbooks: `docs/`, `infra/`, `bootstrap/`, `gitops/`.  
Learning order (Kind): [`knowledge/README.md`](./README.md) steps 0–8.

---

## Decisions we made

| Topic | Decision |
|--------|-----------|
| Cloud vs local | Keep **Kind `dev`** for daily/$0 labs; **AWS `aws-dev`** for real VPC/EC2/kubeadm. |
| AWS Kubernetes | **Not EKS** for cost learning (~$73/mo control plane); **kubeadm on 2 EC2** (CP + worker). |
| AWS provisioning | **Terraform**, learned **incrementally** (VPC → SG → EC2), not one big bang. |
| kubeadm on nodes | **Manual over SSH first** (CKA); not user-data automation in wave 1. |
| Ingress on AWS | Needs **AWS Cloud Controller Manager** for `LoadBalancer` (unlike Kind hostPort). **Not implemented yet** in repo. |
| Knowledge split | Ingress / cert-manager / Argo TLS are **separate** Kind guides (steps 4–6). |
| Cheaper AWS alt | k3s on 1 EC2 is cheaper; we chose **kubeadm + 2 EC2** for **CKA** experience. |

---

## What is implemented in the repo

### Kind path (complete)

- Scripts: `kind-up.sh`, `gitops-start.sh`, bootstrap.
- GitOps: `gitops/clusters/dev/`.
- Guides: `knowledge/00-prerequisites.md` … `06-argocd-ingress-tls.md`, `storage.md`, `08-whats-next.md`.

### AWS path (partial)

| Done | Location |
|------|----------|
| Terraform modules (VPC, SG, 2× EC2, EIP, SSH key) | [`infra/terraform/aws-kubeadm/`](../infra/terraform/aws-kubeadm/) |
| Env `aws-dev` | [`environments/aws-dev/`](../infra/terraform/aws-kubeadm/environments/aws-dev/) |
| Lesson AWS-0 → AWS-15 (infra) | [`09-aws-terraform-learning-path.md`](./09-aws-terraform-learning-path.md) |
| kubeadm K-1 → K-4 | [`10-aws-kubeadm-cluster.md`](./10-aws-kubeadm-cluster.md) |
| Platform on AWS placeholder | [`11-aws-platform-gitops.md`](./11-aws-platform-gitops.md) |

### Not done yet (explicit next wave)

- **`bootstrap/argocd/values/overlays/aws-dev.yaml`**
- **`gitops/clusters/aws-dev/`** (ingress `LoadBalancer` values, cert-manager, certificates)
- **AWS CCM** + IAM instance profile (Lesson **P-1**)
- **`scripts/aws-*`** wrapper optional
- Deeper plan file (Cursor): `cloud_learning_migration` plan — kubeadm + Terraform lesson map

---

## Learning flow (AWS) — do in order

```text
AWS-0  Account, IAM, aws cli, terraform install
AWS-1  terraform init + terraform.tfvars (admin_cidr = your IP/32)
AWS-2–4  VPC, subnet/IGW, security groups (apply incrementally or full)
AWS-5  create_worker = false → CP EC2 + SSH
AWS-6  create_worker = true → worker EC2
AWS-7  Save terraform outputs (EIP, ssh command, kubeadm endpoint)
K-1–K-4  kubeadm + Calico + kubeconfig → .kube/aws-dev.yaml
P-1–P-3  CCM + bootstrap aws-dev + gitops aws-dev  ← NOT IN REPO YET
AWS-15  kubeadm reset → terraform destroy
```

Guide: [`09-aws-terraform-learning-path.md`](./09-aws-terraform-learning-path.md) → [`10-aws-kubeadm-cluster.md`](./10-aws-kubeadm-cluster.md) → [`11-aws-platform-gitops.md`](./11-aws-platform-gitops.md).

---

## Commands cheat sheet (AWS infra)

```bash
cd infra/terraform/aws-kubeadm/environments/aws-dev
cp terraform.tfvars.example terraform.tfvars
# admin_cidr = "<curl ifconfig.me>/32"
terraform init && terraform plan && terraform apply
terraform output ssh_cp_command
```

After kubeadm (Mac):

```bash
source scripts/kubeconfig-setup.sh .kube/aws-dev.yaml
kubectl get nodes
```

---

## How to resume with an assistant

1. Open this file and [`09-aws-terraform-learning-path.md`](./09-aws-terraform-learning-path.md).
2. Say where you stopped (e.g. “finished AWS-6, starting K-2” or “cluster is Ready, implement P-1–P-3”).
3. Ask for one wave at a time, e.g.:
   - *“Implement Wave 4: aws-dev bootstrap overlay + gitops/clusters/aws-dev + CCM doc.”*
   - *“I’m stuck on kubeadm join — worker NotReady.”*
   - *“Update 00-continue-context after we finish P-3.”*

---

## Related files outside knowledge/

| File | Role |
|------|------|
| [`docs/platform-lifecycle.md`](../docs/platform-lifecycle.md) | Day 0 / 1 / 2 model |
| [`infra/terraform/README.md`](../infra/terraform/README.md) | Terraform slot + link to aws-kubeadm |
| [`.gitignore`](../.gitignore) | Ignores `terraform.tfvars`, `*.tfstate`, `.ssh/*.pem` |

---

## Open questions / when you return

- [ ] Which AWS region you locked to (default in tfvars: `us-east-1`).
- [ ] Whether EC2 + kubeadm cluster is up and `kubectl get nodes` works from Mac.
- [ ] Whether to implement **P-1–P-3** next or add **S3 remote state** for Terraform.
- [ ] DNS domain for Argo on AWS (or stay with self-signed + LB hostname for lab).

Update the checklist above as you progress.
