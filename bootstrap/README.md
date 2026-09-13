# Day 1 — Argo CD

```text
bootstrap/argocd/values.yaml              Helm
sensitive/bootstrap/bootstrap.env         optional env (gitignored)
sensitive/bootstrap/secrets/*.yaml        kubectl apply (gitignored)
```

```bash
cp sensitive/bootstrap/secrets/repo.k8s-platform.yaml.example \
   sensitive/bootstrap/secrets/repo.k8s-platform.yaml
./bootstrap/bootstrap.sh
```

Kind (Day 0 + Day 1): `./scripts/bootstrap/up.sh`

UI (no ingress):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Then open http://localhost:8080 (user `admin`).

