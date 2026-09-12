# ingress-nginx (platform ingress)

**Common GitOps app.** Question: “How does HTTP/S traffic reach Services inside the cluster?”

**Depends on:** [core.md](./core.md) (`git push`, `./scripts/gitops/start.sh dev`).

**Next:** [cert-manager](./cert-manager.md).

---

## Mental model

```text
Browser / curl
      ↓
Host localhost:8080 or :8443     (Kind extraPortMappings)
      ↓
Kind node ports 80 / 443
      ↓
ingress-nginx controller (hostPort)
      ↓
Ingress resource → Service → Pod
```

Without an ingress controller, `Ingress` objects do nothing. This repo installs **ingress-nginx** as the first platform app after the AppProject.

## How it is installed (Day 2 GitOps)

| Item | Value |
|------|--------|
| Argo Application | `ingress-nginx` |
| Sync wave | `10` (before cert-manager) |
| Manifest | [`gitops/clusters/dev/core/applications/ingress-nginx.application.yaml`](../../gitops/clusters/dev/core/applications/ingress-nginx.application.yaml) |
| Helm chart | `ingress-nginx` from `https://kubernetes.github.io/ingress-nginx` |
| Values | [`gitops/apps/ingress-nginx/values.yaml`](../../gitops/apps/ingress-nginx/values.yaml) (multi-source `$values/...`) |
| Target namespace | `ingress-nginx` |

Argo **core-apps** syncs the Application CR; Argo **ingress-nginx** syncs the Helm release.

## Kind vs cloud (same app, different values)

This Application is **shared**. Kind maps host ports so you can hit ingress without a cloud load balancer:

[`infra/terraform/environments/kind`](../../infra/terraform/environments/kind/) maps:

```text
host 8080 → node 80
host 8443 → node 443
```

Kind values enable **hostPort** and `ClusterIP`. On AWS/OpenStack, keep the same Application and change values to `LoadBalancer` (needs a cloud controller). Do not copy the GitOps tree.

```yaml
# gitops/apps/ingress-nginx/values.yaml (concept)
controller:
  ingressClassResource:
    name: nginx
    default: true
  hostPort:
    enabled: true
  service:
    type: ClusterIP
```

Later, Argo CD ingress uses `ingressClassName: nginx`. On Kind you open **https://argocd.dev:8443** ([argocd-tls.md](./argocd-tls.md)).

## Verify

After GitOps sync:

```bash
kubectl get applications -n argocd ingress-nginx
kubectl get pods -n ingress-nginx
kubectl get ingressclass
# expect IngressClass "nginx" (default)
```

## Checklist

- [ ] Ingress controller vs `Ingress` resource
- [ ] Why sync-wave `10` runs before cert-manager
- [ ] Why Kind uses hostPort + 8080/8443 and cloud uses `LoadBalancer` — same Application, different values

**Next:** [cert-manager](./cert-manager.md)
