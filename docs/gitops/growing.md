# Growing GitOps

GitOps is the **growth path** for this platform. Infra stays env-specific; bootstrap stays the Argo CD install. Every new platform component is another Application under `gitops/`.

## Already in Git

ingress-nginx, cert-manager, core-certificates, kyverno, core-policies — see [README.md](./README.md).

## Add next (same pattern)

1. Helm values under `gitops/apps/<name>/`
2. Application under `gitops/clusters/dev/core/applications/`
3. Adjust `core.appproject.yaml` and `sync-wave` if there are dependencies
4. Push Git; let Argo sync — avoid one-off `kubectl apply` except the `core-apps` seed

| Candidate | Why it fits GitOps |
|-----------|-------------------|
| [Storage / CSI](./storage.md) | PVCs, OpenEBS as a core Application |
| Observability | kube-prometheus-stack (or similar) as a core Application |
| Secrets | External Secrets Operator + a non-git backend — never commit secrets |
| Team apps | Separate AppProject (not `core`) for sample workloads |

Kind vs AWS vs OpenStack does **not** get a forked GitOps repo. Overlay Helm values (Service type, DNS) when an environment cannot use Kind `hostPort`.

**Back:** [docs/README.md](../README.md) · [gitops catalog](./README.md)
