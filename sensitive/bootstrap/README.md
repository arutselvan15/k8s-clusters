# sensitive/bootstrap

| Path | Git? |
|------|------|
| `bootstrap.env.example` | yes — copy to `bootstrap.env` |
| `bootstrap.env` | no — sourced by `bootstrap.sh` |
| `secrets/*.yaml.example` | yes |
| `secrets/*.yaml` | no — applied by `bootstrap.sh` |
| `argocd/values.yaml.example` | yes (unused by the script; extra Helm if you pass it yourself) |

```bash
cp sensitive/bootstrap/secrets/repo.k8s-platform.yaml.example \
   sensitive/bootstrap/secrets/repo.k8s-platform.yaml
./bootstrap/bootstrap.sh
```
