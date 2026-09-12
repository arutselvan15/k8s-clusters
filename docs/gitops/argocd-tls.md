# Argo CD ingress & TLS

**Common pattern** (Helm overlay + GitOps Certificate). Kind currently uses hostname `argocd.dev` and host port **8443**.

**Depends on:**

- [ingress-nginx](./ingress-nginx.md) — routes traffic to `argocd-server`
- [cert-manager](./cert-manager.md) — CRDs + controller for `Certificate`

This step connects **GitOps TLS** (Secret material) with **Day 1 Helm** (Argo server ingress wiring). Same split on every environment.

---

## End state (dev)

| Item | Value |
|------|--------|
| URL | https://argocd.dev:8443 |
| `/etc/hosts` | `127.0.0.1 argocd.dev` |
| TLS Secret | `argocd-server-tls` in namespace `argocd` |
| Ingress class | `nginx` |

Browser port **8443** = Kind host mapping to node **443** (see [ingress-nginx](./ingress-nginx.md)). Cloud clusters use the load-balancer hostname/port instead.

## Two owners (remember this)

| Concern | Owner | What |
|---------|--------|------|
| TLS Secret **contents** | Day 2 GitOps — **`core-certificates`** | `ClusterIssuer` + `Certificate` → Secret |
| Argo **Ingress** object (host, class, `secretName`) | Day 1 Helm — [`bootstrap/argocd/values.yaml`](../../bootstrap/argocd/values.yaml) | Enables ingress, points at Secret name |

Helm: *“mount Secret `argocd-server-tls` on ingress.”*  
GitOps: *“create that Secret via cert-manager.”*

```text
core-certificates (GitOps)          bootstrap.sh (Helm) — after cert Ready
──────────────────────────          ─────────────────────────────────────────
ClusterIssuer selfsigned       →    (issuer must exist first)
Certificate argocd-server-tls  →    writes Secret argocd-server-tls
                                    ↓ Certificate Ready
./bootstrap/bootstrap.sh   →    server.ingress enabled + secretName set
```

First bootstrap (during `scripts/bootstrap/up.sh`) can run **before** the Secret exists. **Re-run** bootstrap after the Certificate is **Ready**.

## GitOps: Application `core-certificates`

| Item | Value |
|------|--------|
| Sync wave | `25` (after cert-manager) |
| Manifest | [`gitops/clusters/dev/core/applications/core-certificates.application.yaml`](../../gitops/clusters/dev/core/applications/core-certificates.application.yaml) |
| Git path | [`gitops/clusters/dev/core/certificates/`](../../gitops/clusters/dev/core/certificates/) |

Key files:

| File | Role |
|------|------|
| [`clusterissuer-selfsigned.yaml`](../../gitops/clusters/dev/core/certificates/clusterissuer-selfsigned.yaml) | Dev-only issuer (not public CA trust) |
| [`argocd-server-certificate.yaml`](../../gitops/clusters/dev/core/certificates/argocd-server-certificate.yaml) | `dnsNames: [argocd.dev]`, `secretName: argocd-server-tls` |

`secretName` and DNS must match Helm (`hostname`, `server.ingress.secretName` in `bootstrap/argocd/values.yaml`).

## Helm: Argo server ingress (Day 1)

[`bootstrap/argocd/values.yaml`](../../bootstrap/argocd/values.yaml):

- `server.ingress.enabled: true`, `ingressClassName: nginx`, `hostname: argocd.dev`
- `server.ingress.tls: true`, `secretName: argocd-server-tls`
- `configs.params.server.insecure: true` — TLS terminates at **ingress**; ingress uses HTTP to the Argo pod (`backend-protocol: HTTP`)

## Order of operations

1. Cluster + Argo + `git push` + `./scripts/gitops/start.sh dev` (any environment)
2. Wait for sync waves 10 → 20 → 25 (ingress, cert-manager, certs)
3. Confirm Certificate:

   ```bash
   kubectl get applications -n argocd
   kubectl get certificate -n argocd argocd-server-tls
   # STATUS Ready
   ```

4. `./bootstrap/bootstrap.sh`
5. Open https://argocd.dev:8443 on Kind (admin password: [bootstrap](../bootstrap/argocd.md))

Until the Certificate is Ready, use port-forward from [bootstrap/argocd.md](../bootstrap/argocd.md).

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| `Certificate` CRD not found | CR YAML under `applications/` instead of `certificates/` |
| Certs listed under `core-apps` | Wrong sync path; use `core/applications/` only for core-apps |
| Ingress 404 | ingress-nginx not Synced or wrong `ingressClassName` |
| Browser TLS error | Certificate not Ready, or bootstrap not re-run after Ready |
| Wrong cert name | `secretName` mismatch between Certificate and Helm overlay |

## Checklist

- [ ] `core-certificates` vs `cert-manager` Application roles
- [ ] Why TLS YAML is GitOps but ingress **enable** is Helm
- [ ] Why bootstrap runs again after `Certificate` Ready
- [ ] TLS at ingress vs `server.insecure` to the pod

**Next:** [storage.md](./storage.md) (planned app) · [growing.md](./growing.md) · catalog [README.md](./README.md)
