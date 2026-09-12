# GitOps (Day 2) — common, growing

Same app catalog on every cluster. Day 0 only changes **where** Kubernetes runs; Day 2 declares **what** runs.

Argo CD (from [bootstrap](../bootstrap/)) syncs this tree from Git. Add a new platform component here once — do not copy GitOps per cloud.

## Seed (once per cluster)

```bash
source scripts/lib/kubeconfig-setup.sh clusters/<env>/kubeconfig
git push origin main          # Argo clones GitHub, not your laptop
./scripts/gitops/start.sh dev
```

Concepts: [core.md](./core.md) · Operational: [`gitops/README.md`](../../gitops/README.md)

## Apps in this repo

| Wave | App | Guide | Role |
|------|-----|--------|------|
| −1 | AppProject `core` | [core.md](./core.md) | Who may sync what |
| 10 | ingress-nginx | [ingress-nginx.md](./ingress-nginx.md) | HTTP/S into the cluster |
| 20 | cert-manager | [cert-manager.md](./cert-manager.md) | TLS CRDs + controller |
| 25 | core-certificates | [argocd-tls.md](./argocd-tls.md) | `Certificate` / ClusterIssuer CRs |
| 30 | kyverno | [core.md](./core.md) | Admission controller |
| 35 | core-policies | [`gitops/README.md`](../../gitops/README.md) | ClusterPolicy CRs |
| — | storage (planned) | [storage.md](./storage.md) | PV/PVC labs, later CSI |
| — | next apps | [growing.md](./growing.md) | Observability, ESO, team apps |

Values that **must** differ by environment (Kind `hostPort` vs cloud `LoadBalancer`, DNS names) belong in Helm values or a cluster overlay — not a second GitOps stack.

## Add another app

1. `gitops/apps/<name>/values.yaml`
2. `gitops/clusters/dev/core/applications/<name>.application.yaml` (`project: core`, set `sync-wave`)
3. Update `core.appproject.yaml` if the app needs a new repo or namespace
4. `git push` — `core-apps` registers it; Argo syncs the child Application

**Previous:** [bootstrap](../bootstrap/) · **Lifecycle:** [platform-lifecycle.md](../platform-lifecycle.md)
