# GitHub Actions — Workflows

This directory defines automated continuous integration and security verification pipelines for the `devops-repo`.

---

## 1. Architecture & Repository Separation

The MiniBank project uses a two-repository model:
- **`app-repo`:** Houses microservice application source code and Dockerfiles. Its CI workflow (`docker-publish.yml`) builds multi-stage container images, executes unit/integration tests, and publishes tagged images to GitHub Container Registry (GHCR).
- **`devops-repo` (this repository):** Houses Terraform infrastructure code, Ansible configuration playbooks, Kubernetes manifests, Helm values, and security automation.

> **Note:** The legacy `ci-cd.yaml` build/push stub was removed from this repository as image publishing is the exclusive responsibility of `app-repo`. Deployments to the Kubernetes cluster currently follow the deliberate manual tag-bump procedure documented in `docs/runbook.md`.

---

## 2. Active Workflows

### 2.1 Security Scanning (`security-scan.yaml`)

**Purpose:** Executes automated static security analysis and vulnerability scanning across all repository assets prior to merge.

- **Triggers:**
  - `push` to the `main` branch.
  - `pull_request` targeting `main`.
- **Permissions:** Scoped to least-privilege (`contents: read`).
- **Tooling:** [Aqua Security Trivy](https://github.com/aquasecurity/trivy-action) (`aquasecurity/trivy-action@0.28.0`).
- **Scan Type:** Filesystem (`fs`), evaluating:
  - Infrastructure as Code (IaC) misconfigurations in Terraform (`terraform/`) and Kubernetes (`k8s/`).
  - Base image vulnerabilities in local Dockerfiles (`docker/`).
  - Dependency risks across all configuration files.
- **Enforcement Gate:**
  - `severity: HIGH,CRITICAL`
  - `exit-code: '1'` — The workflow fails the build if any unresolved high or critical vulnerabilities or severe misconfigurations are discovered.

---

## 3. Phase 6 DevSecOps Expansion Plan

As part of Phase 6 (DevSecOps Hardening), this directory will expand to include:
1. **Checkov IaC Scanning:** Deep policy-as-code evaluation against CIS AWS Foundations and Kubernetes benchmarks.
2. **Kubesec Manifest Hardening:** Scoring Kubernetes pod security contexts, capabilities, and volume mounts.
3. **Cosign Verification:** Validating cryptographic signatures on container images pulled from GHCR before deployment.

---

## 4. Secrets Management in Workflows

- **No Hardcoded Credentials:** Never store AWS access keys, SSH private keys, or API tokens in workflow YAML files.
- **GitHub Secrets:** Environment-specific credentials must be configured under **Settings > Secrets and variables > Actions** in the GitHub repository.
- **Automated Tokens:** Where possible, utilize the short-lived, auto-provisioned `GITHUB_TOKEN` rather than long-lived Personal Access Tokens (PATs).