# Terraform (Day 0)

Placeholder for cloud cluster provisioning (EKS, GKE, AKS, etc.).

## Role in the platform model

| Phase | This directory |
|-------|----------------|
| **Day 0** | Define and apply infrastructure so a Kubernetes API exists |
| **Day 1** | Not here — see [`../bootstrap/`](../bootstrap/) |
| **Day 2** | Not here — see [`../gitops/`](../gitops/) |

## Local development

On a Mac, [`../kind/`](../kind/) stands in for Terraform: same **Day 0** slot, different tooling.

**AWS kubeadm lab (Terraform):** [`aws-kubeadm/`](aws-kubeadm/) — 2× EC2 + learning path in [`../../knowledge/09-aws-terraform-learning-path.md`](../../knowledge/09-aws-terraform-learning-path.md).

## Install Terraform

Required for **aws-kubeadm** (not needed for Kind-only local work).

**macOS (Homebrew):**

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

**Verify:** `terraform version` shows **>= 1.5** (matches [`aws-kubeadm/environments/aws-dev/versions.tf`](aws-kubeadm/environments/aws-dev/versions.tf)).

**AWS CLI** (same lab): `brew install awscli`, then `aws configure` and `aws sts get-caller-identity`. See [Lesson AWS-0](../../knowledge/09-aws-terraform-learning-path.md#lesson-aws-0).

Other platforms: [Install Terraform](https://developer.hashicorp.com/terraform/install) (HashiCorp docs).

## When you add Terraform

Suggested layout:

```text
terraform/
├── modules/
│   └── eks/              # example
├── environments/
│   ├── dev/
│   ├── stg/
│   └── prod/
└── README.md
```

Wire each environment to the same profile names (`dev`, `stg`, `prod`) used in Kind and in future GitOps paths under `gitops/clusters/`.

## Outputs

Terraform should expose at minimum:

- `cluster_name`
- A **kubeconfig file path** or raw kubeconfig written to disk in CI (e.g. `.kube/<profile>.yaml`)

## Day 1 after apply

Same as Kind — only Day 0 changes:

```bash
# After terraform apply writes kubeconfig to KUBECONFIG_FILE
source scripts/kubeconfig-setup.sh "$KUBECONFIG_FILE"
./bootstrap/bootstrap.sh prod
```

Later, wrap those steps in `scripts/terraform-up.sh <profile>` mirroring [`../../scripts/kind-up.sh`](../../scripts/kind-up.sh).

Kind is a **local substitute** for this directory in Day 0, not a different lifecycle.
