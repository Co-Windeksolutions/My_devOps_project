 # Security Hardening

This project applies defense-in-depth controls across infrastructure, hosts, containers, and Kubernetes.

## What was hardened

- Terraform isolates environments and separates reusable network, security, logging, DNS, compute, and secrets modules.
- Security groups, network policies, RBAC, and least-privilege service accounts restrict access between layers.
- Kubernetes secrets are reserved for sealed or Vault-referenced values; plaintext credentials do not belong in this repository.
- CI security scanning is defined for container images, Terraform, and Kubernetes manifests.
- Monitoring and runbook documentation support detection and incident response.

## Why

These controls reduce blast radius, prevent accidental secret exposure, make infrastructure changes reviewable, and provide an auditable path from build to deployment.

Report suspected vulnerabilities privately to the project maintainers. See `docs/runbook.md` for initial incident response steps.
