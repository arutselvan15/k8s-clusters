# Bootstrap (Day 1) — common

Same on Kind, AWS, and OpenStack. Installs **Argo CD** and Git clone credentials. Does **not** install ingress, cert-manager, or other apps — those live in [gitops](../gitops/).

Detail: [argocd.md](./argocd.md)

```bash
source scripts/lib/kubeconfig-setup.sh .kube/<kubeconfig>.yaml
./bootstrap/bootstrap.sh dev
```

Kind shortcut (Day 0 Kind + this step): `./scripts/bootstrap/up.sh`

Operational runbook: [`bootstrap/README.md`](../../bootstrap/README.md)

**Next:** [gitops](../gitops/)
