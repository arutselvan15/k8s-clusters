# AGENTS.md

## Project purpose

This repository provisions Kubernetes clusters on Kind, AWS EC2, and OpenStack. The project separates:

- `clusters/`: committed cluster config and cluster definitions
- `infra/`: Terraform for cloud infrastructure
- `scripts/`: orchestration scripts for bring-up and teardown
- `docs/`: operational docs and prerequisites
- `sensitive/`: local secrets and generated outputs; do not commit secrets

## Working rules for agents

1. Treat `sensitive/` as protected local data.
   - Do not add credentials, kubeconfigs, cloud configs, or terraform state to version control.
   - If a file under `sensitive/` must be updated, keep it local and avoid committing it unless explicitly requested.

2. Prefer repo-native automation.
   - Use the scripts under `scripts/` for cluster lifecycle actions.
   - Keep changes aligned with the existing shell/Terraform workflow rather than creating one-off ad hoc tooling.

3. Keep changes minimal and explicit.
   - Make small, focused edits.
   - Preserve the existing directory layout and naming conventions.

4. Validate before finishing.
   - For shell changes, check syntax with the relevant shell parser if possible.
   - For Terraform changes, run the smallest relevant validation command, such as `terraform fmt` and `terraform validate` in the affected environment.

## Repo layout

- `README.md`: project overview and quick start
- `clusters/`: cluster definitions and per-cluster config YAML
- `infra/terraform/environments/`: cloud-specific Terraform environments
- `infra/terraform/modules/`: reusable Terraform modules
- `scripts/infra/`: standard lifecycle commands for each provider
- `scripts/lib/`: shared shell helpers and environment setup
- `docs/`: architecture, prerequisites, and platform docs
- `sensitive/`: environment-specific secrets and generated files

## Common commands

```bash
# Quick start examples
./scripts/infra/up.sh kind k8s-kind
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp

# Tear down
./scripts/infra/down.sh kind k8s-kind
./scripts/infra/down.sh aws k8s-aws
./scripts/infra/down.sh openstack k8s-ocp
```

For provider-specific details, read the relevant docs in `docs/` before making environment-sensitive changes.

## Safety expectations

- Never print or expose secrets from `sensitive/` in logs, commit messages, or issue text.
- Prefer placeholders and examples, not real credentials.
- When updating cluster config, ensure it remains consistent across the relevant `clusters/`, `scripts/`, and `docs/` references.

## Suggested change checklist

Before concluding work:

- Confirm the change fits this repo’s cluster automation model.
- Check whether any script, README, or doc should also be updated.
- Validate the affected shell or Terraform workflow.
- Ensure no sensitive files were added to the patch.
