# Day 1 — Bootstrap (Argo CD)

```text
./bootstrap/bootstrap.sh
        ├── source  sensitive/bootstrap/bootstrap.env
        ├── helm    bootstrap/argocd/values.yaml
        └── apply   sensitive/bootstrap/secrets/*.yaml
```

```bash
./bootstrap/bootstrap.sh
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Open http://localhost:8080 (no ingress).
