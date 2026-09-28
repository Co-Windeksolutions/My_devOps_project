# Project Roadmap: Multi-Tier Microservices on AWS with Terraform, Ansible, Kubernetes & DevSecOps

## What This Project Is

A production-style deployment pipeline that takes a multi-service application from raw AWS infrastructure to a running, monitored, security-hardened Kubernetes cluster — entirely through code. It proves you understand the full lifecycle: **provision → configure → orchestrate → automate → secure → observe.**

**Project 1** builds the working system. **Project 2** hardens it with DevSecOps practices. Same repo, staged as two clear phases in your commit history.

## The Application: MiniBank (4 Microservices)

- **API Gateway** — single entry point, routes to downstream services, calls IAM's `/validate` for auth (no local JWT reimplementation), basic in-memory rate limiting
- **IAM** — registration/login, JWT issuance, RBAC, Postgres-backed
- **Wallet/Ledger** — `check_balance` / `transfer_funds`, double-entry bookkeeping (append-only ledger), holds KYC status, publishes transfer events, Postgres-backed
- **Notification** — consumes transfer events off the message broker, logs mock email/SMS, no DB

All 4 built in **Python** (FastAPI/SQLAlchemy/Alembic), same stack and patterns across services for consistency. Infra dependencies (Postgres, RabbitMQ) are deployed via Helm chart, not built as custom services. No custom frontend — Swagger/OpenAPI UI, Postman+Newman in CI, and k6 load testing serve as the interaction/demo layer instead.

## Repo Split

Two separate repos, not one monorepo:

- **`app-repo`** — the 4 microservices above. Built primarily via AI-assisted generation (Google Antigravity, Claude Sonnet 4.6) constrained by a written procedure-rules file: app code only, one service at a time, mandatory review before proceeding to the next. Dockerfiles, `.dockerignore`, and `.gitignore` are written by hand, not generated — packaging/deploy artifacts stay yours even though the app logic is AI-assisted.
- **`devops-repo`** — Terraform, Ansible, Kubernetes, CI/CD, security. This is what the project is actually proving. Built primarily by hand (~70% you / ~30% AI-assisted as a second opinion, not a builder). The `devops-repo` references `app-repo`'s built images (pulled from a registry) exactly like a real platform engineer working against a service they didn't write.

Everything in the **Repo File Tree** and **Build Order** sections below describes the `devops-repo`. The Docker phase produces images that get pushed to a registry; `app-repo` is where the Dockerfiles/app code actually live.

**Important: separate repos don't sync automatically — the container registry is the interface between them, not repo access.** In industry, developers never get push access to `devops-repo`, and DevOps engineers don't build images by hand. The real flow: `app-repo`'s own CI automatically builds and pushes a tagged image to the registry on every merge to main — no manual `docker build`/`docker push` per feature. `devops-repo` never builds images, it only deploys whatever tag is in the registry. The handoff from "new image exists" to "cluster is updated" is itself automated via either a CI trigger (`app-repo`'s pipeline fires a `repository_dispatch` that updates the tag in `devops-repo`) or GitOps (ArgoCD/Flux watching the registry directly and syncing automatically). Manually bumping the image tag yourself is a fine first step *while learning* to see the handoff clearly, but the real target is one of the two automated patterns above — don't leave it manual long-term.

## Documentation Standard

Every major directory gets its own `README.md`, not just the root:
- `terraform/README.md` — what this provisions, key decisions (why multi-AZ, NAT strategy, SG vs NACL reasoning)
- `ansible/README.md` — what each role does, how to run it
- `k8s/README.md` — architecture, why ConfigMaps/Secrets are mounted as volumes not env vars
- `.github/workflows/README.md` — what each workflow does, trigger conditions

These serve two purposes: your own record of *why* each decision was made (useful when explaining it in interviews later), and what a recruiter actually reads instead of digging through raw YAML.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Cloud | AWS |
| Infrastructure as Code | Terraform |
| Configuration Management | Ansible |
| Containers | Docker |
| Container Registry | GHCR (GitHub Container Registry) |
| Orchestration | Kubernetes |
| CI/CD | GitHub Actions |
| Secrets | AWS Secrets Manager (Vault optional/stretch — see Phase 1) |
| Monitoring | Prometheus + Grafana |
| Security (Project 2) | Trivy, Checkov/kubesec, OPA/Kyverno, Falco, cosign |
| Tracing (Project 2) | OpenTelemetry + Jaeger/Tempo |

---

## Phase 1 — Terraform: Infrastructure

**Goal:** Provision everything Kubernetes and your app will run on, with no manual console clicks.

- Remote backend: S3 bucket for state files + DynamoDB table for state locking
- **S3 logging bucket per environment** — separate from the state bucket, used for VPC Flow Logs, ALB/ingress access logs, and optionally CloudTrail logs for that environment. Keep this a distinct module/bucket per environment (dev logs shouldn't mix with prod logs) with a lifecycle policy (e.g. expire logs after 30-90 days) so it doesn't grow unbounded
- VPC with **subnets across multiple Availability Zones** (minimum 2 AZs) — public subnets for load balancers/bastion, private subnets for app/DB workloads
- Internet Gateway + NAT Gateway(s) — one NAT per AZ if you want true HA, or one shared NAT to save cost (document which you chose and why)
- Route tables associated per subnet/AZ
- **Security Groups** — scoped tightly per resource (not `0.0.0.0/0` everywhere), e.g. separate SGs for bastion, app nodes, DB
- **Network ACLs (NACLs)** — subnet-level stateless rules as a second layer of defense behind Security Groups (document why you added both — SGs are stateful/instance-level, NACLs are stateless/subnet-level, so together they show defense-in-depth)
- EC2 instance(s) — either as k8s nodes (if self-managed) or a bastion/jump box if using EKS
- ~~Route53 — DNS records pointing to your app/ingress~~ **Skipped.** Using the ALB/Ingress's auto-generated AWS DNS name directly (e.g. `k8s-xxxxx.us-east-1.elb.amazonaws.com`) instead of buying a domain and provisioning Route53 records. Loses nothing in DevOps signal — VPC, EC2, Ingress, and K8s routing are still fully demonstrated. Revisit later only if you want a cleaner-looking demo URL for a portfolio README (~$10-12/year for a domain + Route53 hosted zone if so).
- Terraform Cloud or Workspaces for state/environment separation (e.g. dev vs prod workspace)
- **AWS Secrets Manager** — primary secrets store (DB credentials, JWT signing key, broker credentials). Chosen over self-hosting Vault: simpler to provision via Terraform, integrates cleanly with EC2 IAM roles, and is what most AWS shops actually use day-to-day for this scale of project. Avoids Vault's real operational overhead (init/unseal/auth-method setup) for a project on a solo timeline.
- ~~Vault~~ **Dropped from the required path.** Optional stretch goal at the end of Project 2 if time allows — "additionally explored Vault for dynamic secrets" is a fine bonus README line, but it shouldn't block anything else. Revisit only once Secrets Manager (or Sealed Secrets for K8s specifically, already in Phase 6) is working end-to-end.

**Why AZs matter here:** this is what turns "I provisioned a VPC" into "I understand high availability." Spreading subnets and eventually your k8s nodes across 2+ AZs means a single AZ failure doesn't take your whole app down — a real production concern, and a strong talking point in interviews.

### Writing This as Modules (Dev / Staging / Prod)

Instead of one flat set of `.tf` files, write reusable **modules**, then call them differently per environment:

- Each module is self-contained: `main.tf` (resources), `variables.tf` (inputs), `outputs.tf` (what it exposes to other modules/environments) — e.g. the `vpc` module takes a CIDR block and AZ list as input, outputs subnet IDs and VPC ID for the `ec2` or `eks` module to consume
- Root-level environment folders (`environments/dev`, `environments/staging`, `environments/prod`) each just **call the modules** with different variable values (smaller instance sizes + single NAT for dev, full multi-AZ NAT + larger instances for prod) — no duplicated resource code, only different inputs
- Each environment has its own state file (separate S3 key per environment, or separate Terraform Cloud workspace) so `terraform apply` in dev can never accidentally touch prod
- Start by writing one module (e.g. `vpc`) fully by hand, get it working for dev, then reuse it unchanged for staging/prod by just passing different variables — that's the moment the "why modules" concept actually clicks

---

## Phase 2 — Ansible: Configuration

**Goal:** Take the raw EC2 instances Terraform created and configure them — installing dependencies, hardening OS-level settings, and preparing them to run Kubernetes components (if self-managed) or supporting tooling.

- Playbook built using **Ansible roles** (not one flat playbook) — separate roles per concern, e.g. `common`, `docker`, `k8s-prereqs`, `monitoring-agent`
- Inventory reflecting your multi-AZ EC2 instances
- Idempotent tasks — running the playbook twice shouldn't break anything

---

## Phase 3 — Docker: Containerize the App

**Goal:** Package each of the 4 microservices (API Gateway, IAM, Wallet/Ledger, Notification) into images.

**Note: this lives in `app-repo`, not `devops-repo`.** The Dockerfile needs the app's source code as its build context, so it belongs next to the code, not in the infra repo. `devops-repo` never holds a Dockerfile — it only references the built image by tag (see Kubernetes phase below).

- Dockerfile per service (4 total), multi-stage builds (builder stage installs deps into a venv, runtime stage is slim + non-root user)
- `.dockerignore` per service — excludes secrets, `__pycache__/`, venvs, `tests/`, and the Dockerfile/`.dockerignore` themselves from the built image
- README for the Docker project (in `app-repo`) — base image choice and why, multi-stage reasoning, how to build/run locally, what ports each service exposes
- CI in `app-repo` builds each service's image and pushes it to GHCR with a tag, e.g. `ghcr.io/yourname/iam-service:v1.2`

**Registry choice: GHCR (GitHub Container Registry)** — chosen over Docker Hub for zero extra credential setup (GitHub Actions gets an auto-provisioned `GITHUB_TOKEN`, no separate access token to create/store), no free-tier pull rate limits to worry about, and everything staying under one GitHub account alongside the code and CI/CD workflow. Docker Hub's native Automated Builds feature is also being deprecated (fully retiring April 1, 2027) and requires a paid plan — not a concern here since GHCR is used purely as a push target from GitHub Actions, not via any registry-native autobuild feature. Authenticate via `docker/login-action` using `GITHUB_TOKEN`; workflow does `docker build` → `docker push` to `ghcr.io/...` on merge to main.

---

## Phase 4 — Kubernetes: Orchestration

**Goal:** Run the 4 containerized microservices as a resilient, configurable, access-controlled system.

- **Deployment** resources (which create ReplicaSets, which create Pods) — one per microservice (API Gateway, IAM, Wallet/Ledger, Notification)
- **Services** — ClusterIP for internal communication; only API Gateway exposed externally, via Ingress
- **Ingress** — single entry point routing to API Gateway; accessed via the ALB/Ingress's auto-generated AWS DNS name (Route53 skipped — see Phase 1)
- **ConfigMaps + Secrets mounted as volumes** — each service reads config from mounted files (DB connection strings for IAM/Wallet-Ledger, broker connection for Wallet-Ledger/Notification, JWT signing key for IAM) rather than env-var-only config
- **RBAC** — scoped service accounts per service, not cluster-admin
- **Helm charts** for the infra dependencies (PostgreSQL, RabbitMQ) — deployed as-is, no custom app code written for these
- **Alembic migrations as a K8s initContainer** on IAM and Wallet/Ledger — runs before the app container starts, so the app itself never applies its own schema changes at boot (least privilege: the running app doesn't need DB DDL permissions)
- Node/pod distribution across your multi-AZ setup — use topology spread constraints or anti-affinity rules so replicas don't all land on one AZ
- Detailed note on K8s architecture (`docs/k8s-architecture.md`) — diagram + explanation of how the 4 services, Ingress, ConfigMaps/Secrets, and Helm-deployed dependencies all connect

---

## Phase 5 — GitHub Actions: CI/CD

**Goal:** Automate build → test → push → deploy on every change.

- Workflow triggered on push/PR to main
- Docker used as the build step/agent (build image per service → tag → push to GHCR)
- Deploy stage applies updated manifests to the cluster (or triggers ArgoCD sync, if you add GitOps later)
- Secrets (GHCR auth via `GITHUB_TOKEN`, kubeconfig) stored in GitHub Actions secrets, not hardcoded
- Postman/Newman collection run against the deployed services as an automated API test stage
- k6 load test stage to validate observability/autoscaling once Prometheus/Grafana are in place (Project 2)

---

## Phase 6 — Project 2: DevSecOps Hardening

Builds on the exact same repo, added as a clearly separate stage in your commit history/README.

1. Trivy — scan images in the pipeline, fail build on critical CVEs
2. Checkov (Terraform) + kubesec (K8s manifests) — catch misconfigurations before deploy
3. Secrets fully migrated to Vault (if not already done in Phase 1)
4. Network Policies — explicit pod-to-pod traffic rules
5. OPA/Gatekeeper or Kyverno — cluster-wide policy enforcement (no root containers, approved registries only)
6. Falco — runtime anomaly detection
7. cosign — image signing
8. Prometheus + Grafana — metrics, dashboards, real alert rules
9. OpenTelemetry + Jaeger/Tempo — distributed tracing across the 4 services and the message broker
10. Optional: ArgoCD for GitOps-based deployment

---

## Repo File Tree

```
project-root/
├── README.md                     # Project overview, architecture diagram, how to run
├── SECURITY.md                   # Project 2 write-up: what was hardened and why
│
├── terraform/
│   ├── README.md                 # what this provisions + key decisions
│   ├── modules/
│   │   ├── vpc/
│   │   │   ├── main.tf            # VPC, subnets across AZs, route tables
│   │   │   ├── variables.tf       # CIDR, AZ list, etc. as inputs
│   │   │   └── outputs.tf         # VPC ID, subnet IDs for other modules
│   │   ├── security/
│   │   │   ├── main.tf            # Security Groups + NACLs
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── logging/
│   │   │   ├── main.tf            # S3 log bucket, lifecycle policy, VPC Flow Logs config
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ec2/
│   │   └── secrets-manager/
│   │
│   └── environments/
│       ├── dev/
│       │   ├── main.tf            # calls modules with dev-sized inputs
│       │   ├── backend.tf         # dev-specific state key/workspace
│       │   └── terraform.tfvars
│       ├── staging/
│       │   ├── main.tf
│       │   ├── backend.tf
│       │   └── terraform.tfvars
│       └── prod/
│           ├── main.tf            # same modules, prod-sized inputs (multi-AZ NAT, etc.)
│           ├── backend.tf
│           └── terraform.tfvars
│
├── ansible/
│   ├── README.md                 # what each role does, how to run it
│   ├── inventory/
│   │   └── hosts.ini
│   ├── playbook.yml
│   └── roles/
│       ├── common/
│       ├── docker/
│       ├── k8s-prereqs/
│       └── monitoring-agent/
│
├── docker/                        # NOTE: lives in app-repo, shown here only for reference
│   ├── api-gateway/
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── iam-service/
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── wallet-service/
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── notification-service/
│   │   ├── Dockerfile
│   │   └── README.md
│   └── docker-compose.yml        # for local dev/testing
│
├── k8s/
│   ├── README.md                 # architecture + config decisions
│   ├── namespace.yaml
│   ├── deployments/
│   │   ├── api-gateway-deployment.yaml
│   │   ├── iam-deployment.yaml
│   │   ├── wallet-ledger-deployment.yaml
│   │   └── notification-deployment.yaml
│   ├── services/
│   ├── ingress/
│   │   └── ingress.yaml
│   ├── configmaps/
│   ├── secrets/                  # sealed/vault-referenced, never plaintext
│   ├── rbac/
│   │   ├── roles.yaml
│   │   └── rolebindings.yaml
│   ├── helm-values/              # PostgreSQL + RabbitMQ Helm chart values
│   ├── network-policies/         # Phase 6
│   └── policies/                 # OPA/Kyverno policies, Phase 6
│
├── .github/
│   └── workflows/
│       ├── README.md             # what each workflow does, triggers
│       ├── ci-cd.yaml            # build, test, push, deploy
│       └── security-scan.yaml    # Phase 6: Trivy, Checkov, kubesec
│
├── monitoring/
│   ├── prometheus/
│   └── grafana/
│       └── dashboards/
│
└── docs/
    ├── architecture.md
    ├── k8s-architecture.md
    └── runbook.md                # incident response basics
```

---

## Build Order (What to Actually Do, In Sequence)

1. Terraform: write the `vpc` module (multi-AZ) → apply it via `environments/dev` → commit
2. Terraform: write `security` module (SGs/NACLs) + `logging` module (per-env S3 log bucket, VPC Flow Logs) + `ec2`, `secrets-manager` modules → wire into dev → commit
3. Terraform: create `staging`/`prod` environment folders reusing the same modules with different inputs → commit
4. Ansible: roles + playbook against the EC2 instances → commit
5. Docker: confirm all 4 services build and run locally (already in progress in `app-repo`) → commit
6. Kubernetes: Deployments/Services for all 4 services + Helm-deployed Postgres/RabbitMQ, get it running → commit
7. Kubernetes: add Ingress, ConfigMaps/Secrets as volumes, RBAC, Alembic initContainers → commit
8. GitHub Actions: get build → push (to GHCR) working → commit
9. GitHub Actions: add the deploy stage → commit
10. Write docs (architecture, K8s architecture, runbook) → commit
11. **— Project 1 complete, tag a release —**
12. Move into Phase 6 security hardening, one tool per commit

Each numbered step is a real commit with a real message. That commit history is your proof of process, not just a finished product.
