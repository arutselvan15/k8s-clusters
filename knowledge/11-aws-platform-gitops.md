# AWS platform GitOps (aws-dev) — coming next

**Prerequisites:** [10-aws-kubeadm-cluster.md](./10-aws-kubeadm-cluster.md) (kubectl from Mac works).

This repo’s **Kind `dev`** path is fully implemented. **`aws-dev`** GitOps/bootstrap overlays are **planned** in a follow-up change:

| Lesson | Topic | Status |
|--------|--------|--------|
| **P-1** | IAM instance profile + [AWS Cloud Controller Manager](https://cloud-provider-aws.sigs.k8s.io/) (LoadBalancer Services) | Not in repo yet |
| **P-2** | `bootstrap/argocd/values/overlays/aws-dev.yaml` + `./bootstrap/bootstrap.sh aws-dev` | Not in repo yet |
| **P-3** | `gitops/clusters/aws-dev/` (ingress `LoadBalancer`, cert-manager, certificates) + `gitops-start.sh aws-dev` | Not in repo yet |

Until then, continue learning on **Kind dev** for Argo CD / ingress / TLS ([README](./README.md) steps 1–6).

**Reference:** Same patterns as Kind — [03-day2-gitops-core.md](./03-day2-gitops-core.md), [04](./04-ingress-nginx.md)–[06](./06-argocd-ingress-tls.md), with ingress values using **LoadBalancer** instead of Kind `hostPort`.

Back: [09-aws-terraform-learning-path.md](./09-aws-terraform-learning-path.md)
