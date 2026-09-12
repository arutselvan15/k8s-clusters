# Kyverno Chainsaw — policy e2e tests

[Chainsaw](https://kyverno.github.io/chainsaw/) runs declarative end-to-end tests against a live cluster. Use it after **Kyverno** and **`core-policies`** are synced (Day 2 GitOps).

Tests live next to GitOps manifests but are **not** deployed by Argo CD. Run them locally or in CI with `KUBECONFIG` pointed at the cluster under test.

## Prerequisites

- Kyverno Application **Synced**
- `core-policies` Application **Synced**
- [Chainsaw CLI](https://kyverno.github.io/chainsaw/latest/quick-start/) on your PATH

```bash
brew install kyverno/tap/chainsaw
```

## Run all policy tests

```bash
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
./scripts/gitops/chainsaw.sh
```

Or run a single scenario:

```bash
chainsaw test gitops/chainsaw/disallow-latest-tag
```

## Layout

```text
gitops/chainsaw/
└── disallow-latest-tag/     # matches core/policies/disallow-latest-tag.yaml
    ├── chainsaw-test.yaml
    └── *.yaml                 # fixtures referenced by the test
```

When you add a ClusterPolicy under `gitops/clusters/<profile>/core/policies/`, add a sibling folder here with a `chainsaw-test.yaml` that exercises allow/deny behavior.
